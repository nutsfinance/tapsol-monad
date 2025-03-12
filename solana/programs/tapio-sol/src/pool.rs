use crate::{errors, state};
use anchor_lang::prelude::*;

const A_PRECISION: u128 = 100u128;
const FEE_PRECISION: u64 = 10_000_000_000u64;
const NUMBER_OF_ITERATIONS_TO_CONVERGE: i32 = 255;

/// algorithm is based on https://docs.acoconut.fi/asset/acbtc/algorithm
pub fn get_a(a0: u64, t0: u64, a1: u64, t1: u64) -> Option<u64> {
    let current_block: u64 = Clock::get().ok()?.epoch;
    if current_block < t1 {
        let time_diff: u64 = current_block.checked_sub(t0)?;
        let time_diff_div: u64 = t1.checked_sub(t0)?;
        if a1 > a0 {
            let diff = a1.checked_sub(a0)?;
            let amount = diff.checked_mul(time_diff)?.checked_div(time_diff_div)?;
            Some(a0.checked_add(amount)?)
        } else {
            let diff = a0.checked_sub(a1)?;
            let amount = diff.checked_mul(time_diff)?.checked_div(time_diff_div)?;
            Some(a0.checked_sub(amount)?)
        }
    } else {
        Some(a1)
    }
}

pub fn get_d(balances: &[u64], a: u64) -> Option<u64> {
    let zero: u128 = 0u128;
    let one: u128 = 1u128;
    let mut sum: u128 = 0u128;
    let mut ann: u128 = u128::from(a);
    let balance_size: u128 = u128::try_from(balances.len()).ok()?;
    for x in balances.iter() {
        let balance: u128 = u128::from(*x);
        sum = sum.checked_add(balance)?;
        ann = ann.checked_mul(balance_size)?;
    }
    if sum == zero {
        return Some(0u64);
    }

    let mut prev_d: u128;
    let mut d: u128 = sum;
    for _i in 0..NUMBER_OF_ITERATIONS_TO_CONVERGE {
        let mut p_d: u128 = d;
        for x in balances.iter() {
            let balance: u128 = u128::from(*x);
            let div_op: u128 = balance.checked_mul(balance_size)?;
            p_d = p_d.checked_mul(d)?.checked_div(div_op)?;
        }
        prev_d = d;
        let t1: u128 = p_d.checked_mul(balance_size)?;
        let t2: u128 = balance_size.checked_add(one)?.checked_mul(p_d)?;
        let t3: u128 = ann
            .checked_sub(A_PRECISION)?
            .checked_mul(d)?
            .checked_div(A_PRECISION)?
            .checked_add(t2)?;
        d = ann
            .checked_mul(sum)?
            .checked_div(A_PRECISION)?
            .checked_add(t1)?
            .checked_mul(d)?
            .checked_div(t3)?;
        if d > prev_d {
            if d - prev_d <= one {
                break;
            }
        } else if prev_d - d <= one {
            break;
        }
    }
    u64::try_from(d).ok()
}

pub fn get_y(balances: &[u64], token_index: usize, target_d: u64, amplitude: u64) -> Option<u64> {
    let one: u128 = 1u128;
    let two: u128 = 2u128;
    let mut c: u128 = u128::from(target_d);
    let mut sum: u128 = 0u128;
    let mut ann: u128 = u128::from(amplitude);
    let balance_size: u128 = u128::try_from(balances.len()).ok()?;
    let target_d_u256: u128 = u128::from(target_d);

    for (i, balance_ref) in balances.iter().enumerate() {
        let balance: u128 = u128::from(*balance_ref);
        ann = ann.checked_mul(balance_size)?;
        if i == token_index {
            continue;
        }
        sum = sum.checked_add(balance)?;
        let div_op: u128 = balance.checked_mul(balance_size)?;
        c = c.checked_mul(target_d_u256)?.checked_div(div_op)?
    }

    c = c
        .checked_mul(target_d_u256)?
        .checked_mul(A_PRECISION)?
        .checked_div(ann.checked_mul(balance_size)?)?;
    let b: u128 = sum.checked_add(target_d_u256.checked_mul(A_PRECISION)?.checked_div(ann)?)?;
    let mut prev_y: u128;
    let mut y: u128 = target_d_u256;

    for _i in 0..NUMBER_OF_ITERATIONS_TO_CONVERGE {
        prev_y = y;
        y = y.checked_mul(y)?.checked_add(c)?.checked_div(
            y.checked_mul(two)?
                .checked_add(b)?
                .checked_sub(target_d_u256)?,
        )?;
        if y > prev_y {
            if y - prev_y <= one {
                break;
            }
        } else if prev_y - y <= one {
            break;
        }
    }
    u64::try_from(y).ok()
}

/// helper function to determine the mint amount
pub fn get_mint_amount(
    pool_info: &Account<state::PoolState>,
    amounts: &[u64],
) -> Result<MintResult> {
    if 2 != amounts.len() {
        return Err(errors::ErrorCode::ArgumentValidationFailure.into());
    }

    let a: u64 = get_a(
        pool_info.a,
        pool_info.a_block,
        pool_info.future_a,
        pool_info.future_a_block,
    )
    .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    let old_d: u64 = pool_info.total_supply;
    let zero: u64 = 0u64;

    let mut balances: Vec<u64> = pool_info.balances.to_vec();
    for i in 0..balances.len() {
        if amounts[i] == zero {
            if old_d == zero {
                return Err(errors::ErrorCode::ArgumentValidationFailure.into());
            }
            continue;
        }
        let result: u64 = balances[i]
            .checked_add(
                amounts[i]
                    .checked_mul(pool_info.precisions[i])
                    .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?,
            )
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
        balances[i] = result;
    }
    let new_d: u64 =
        get_d(&balances, a).ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    let mut mint_amount: u64 = new_d
        .checked_sub(old_d)
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    let mut fee_amount: u64 = zero;
    let mint_fee: u64 = pool_info.mint_fee;

    if pool_info.mint_fee > zero {
        fee_amount = mint_amount
            .checked_mul(mint_fee)
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?
            .checked_div(FEE_PRECISION)
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
        mint_amount = mint_amount
            .checked_sub(fee_amount)
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    }

    Ok(MintResult {
        mint_amount,
        fee_amount,
        balances,
        total_supply: new_d,
    })
}

/// helper function to determine the swap amount
pub fn get_swap_amount(
    pool_info: &Account<state::PoolState>,
    input_index: usize,
    output_index: usize,
    dx: u64,
) -> Result<SwapResult> {
    let zero: u64 = 0u64;
    let one: u64 = 1u64;
    let balance_size: usize = pool_info.balances.len();
    if input_index == output_index {
        return Err(errors::ErrorCode::ArithmeticError.into());
    }
    if dx <= zero {
        return Err(errors::ErrorCode::ArithmeticError.into());
    }
    if input_index >= balance_size {
        return Err(errors::ErrorCode::ArithmeticError.into());
    }
    if output_index >= balance_size {
        return Err(errors::ErrorCode::ArithmeticError.into());
    }

    let a: u64 = get_a(
        pool_info.a,
        pool_info.a_block,
        pool_info.future_a,
        pool_info.future_a_block,
    )
    .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    let d: u64 = pool_info.total_supply;
    let mut balances: Vec<u64> = pool_info.balances.to_vec();
    balances[input_index] = balances[input_index]
        .checked_add(
            dx.checked_mul(pool_info.precisions[input_index])
                .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?,
        )
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    let y: u64 = get_y(&balances, output_index, d, a)
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    let mut dy: u64 = balances[output_index]
        .checked_sub(y)
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?
        .checked_sub(one)
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?
        .checked_div(pool_info.precisions[output_index])
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    if pool_info.swap_fee > zero {
        let fee_amount: u64 = dy
            .checked_mul(pool_info.swap_fee)
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?
            .checked_div(FEE_PRECISION)
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
        dy = dy
            .checked_sub(fee_amount)
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    }
    Ok(SwapResult {
        dx,
        dy,
        y,
        balance_i: balances[input_index],
    })
}

/// helper function to determine the redeem proportion amount
pub fn get_redeem_proportion_amount(
    pool_info: &Account<state::PoolState>,
    amount_bal: u64,
) -> Result<RedeemProportionResult> {
    let mut amount: u64 = amount_bal;
    let zero: u64 = 0u64;

    if amount <= zero {
        return Err(errors::ErrorCode::ArgumentValidationFailure.into());
    }

    let d: u64 = pool_info.total_supply;
    let mut amounts: Vec<u64> = Vec::new();
    let mut balances: Vec<u64> = pool_info.balances.to_vec();

    let mut fee_amount: u64 = zero;
    if pool_info.redeem_fee > zero {
        fee_amount = amount
            .checked_mul(pool_info.redeem_fee)
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?
            .checked_div(FEE_PRECISION)
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
        // Redemption fee is charged with pool token before redemption.
        amount = amount
            .checked_sub(fee_amount)
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    }

    for i in 0..pool_info.balances.len() {
        let balance_i: u64 = balances[i];
        let diff_i: u64 = balance_i
            .checked_mul(amount)
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?
            .checked_div(d)
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
        balances[i] = balance_i
            .checked_sub(diff_i)
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
        let amounts_i: u64 = diff_i
            .checked_div(pool_info.precisions[i])
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
        amounts.push(amounts_i);
    }
    let total_supply: u64 = d
        .checked_sub(amount)
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    Ok(RedeemProportionResult {
        amounts: amounts.to_vec(),
        balances: balances.to_vec(),
        fee_amount,
        total_supply,
        redeem_amount: amount,
    })
}

/// helper function to determine the redeem single amount
pub fn get_redeem_single_amount(
    pool_info: &Account<state::PoolState>,
    amount_bal: u64,
    i: usize,
) -> Result<RedeemSingleResult> {
    let mut amount: u64 = amount_bal;
    let zero: u64 = 0u64;
    let one: u64 = 1u64;
    if amount <= zero {
        return Err(errors::ErrorCode::ArgumentValidationFailure.into());
    }
    if i >= pool_info.balances.len() {
        return Err(errors::ErrorCode::ArgumentValidationFailure.into());
    }
    let mut balances: Vec<u64> = pool_info.balances.to_vec();
    let a: u64 = get_a(
        pool_info.a,
        pool_info.a_block,
        pool_info.future_a,
        pool_info.future_a_block,
    )
    .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    let d: u64 = pool_info.total_supply;
    let mut fee_amount: u64 = zero;

    if pool_info.redeem_fee > zero {
        fee_amount = amount
            .checked_mul(pool_info.redeem_fee)
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?
            .checked_div(FEE_PRECISION)
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
        // Redemption fee is charged with pool token before redemption.
        amount = amount
            .checked_sub(fee_amount)
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    }

    // The pool token amount becomes D - _amount
    let y: u64 = get_y(
        &balances,
        i,
        d.checked_sub(amount)
            .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?,
        a,
    )
    .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    // dy = (balance[i] - y - 1) / precisions[i] in case there was rounding errors
    let balance_i: u64 = pool_info.balances[i];
    let dy: u64 = balance_i
        .checked_sub(y)
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?
        .checked_sub(one)
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?
        .checked_div(pool_info.precisions[i])
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    let total_supply: u64 = d
        .checked_sub(amount)
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    balances[i] = y;
    Ok(RedeemSingleResult {
        dy,
        fee_amount,
        total_supply,
        balances: balances.to_vec(),
        redeem_amount: amount,
    })
}

#[derive(Clone, Default, PartialEq, Eq, Debug)]
pub struct MintResult {
    pub mint_amount: u64,
    pub fee_amount: u64,
    pub balances: Vec<u64>,
    pub total_supply: u64,
}

#[derive(Clone, Default, PartialEq, Eq, Debug)]
pub struct SwapResult {
    pub dx: u64,
    pub dy: u64,
    pub y: u64,
    pub balance_i: u64,
}

#[derive(Clone, Default, PartialEq, Eq, Debug)]
pub struct RedeemProportionResult {
    pub amounts: Vec<u64>,
    pub balances: Vec<u64>,
    pub fee_amount: u64,
    pub total_supply: u64,
    pub redeem_amount: u64,
}

#[derive(Clone, Default, PartialEq, Eq, Debug)]
pub struct RedeemSingleResult {
    pub dy: u64,
    pub fee_amount: u64,
    pub total_supply: u64,
    pub balances: Vec<u64>,
    pub redeem_amount: u64,
}
