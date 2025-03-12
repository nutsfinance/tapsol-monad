pub mod errors;
pub mod event;
pub mod pool;
pub mod stake;
pub mod state;

use anchor_lang::prelude::*;
use anchor_spl::{
    associated_token::AssociatedToken,
    metadata::{
        create_metadata_accounts_v3, mpl_token_metadata::types::DataV2, CreateMetadataAccountsV3,
        Metadata,
    },
    token::{Burn, Mint, MintTo, Token, TokenAccount, Transfer},
};

declare_id!("GjaQFtZFfsjas9tpb4inKoWvzccuWgNAUHHuFpXKaYjT");

#[program]
pub mod tapio_sol {
    use super::*;

    pub fn initialize_pool(
        ctx: Context<InitializePool>,
        mint_fee: u64,
        swap_fee: u64,
        redeem_fee: u64,
        a: u64,
    ) -> Result<()> {
        crate::initialize_pool(ctx, mint_fee, swap_fee, redeem_fee, a)
    }

    pub fn initialize_token(
        ctx: Context<InitializeToken>,
        token_name: Box<String>,
        token_symbol: Box<String>,
        token_uri: Box<String>,
    ) -> Result<()> {
        crate::initialize_token(ctx, token_name, token_symbol, token_uri)
    }

    pub fn modify_a(ctx: Context<ModifyA>, a: u64, future_a_block: u64) -> Result<()> {
        crate::modify_a(ctx, a, future_a_block)
    }

    pub fn mint(ctx: Context<MintShare>, amounts: Vec<u64>, min_mint_amount: u64) -> Result<()> {
        crate::mint(ctx, amounts, min_mint_amount)
    }

    pub fn swap(ctx: Context<SwapToken>, i: u16, j: u16, dx: u64, min_dy: u64) -> Result<()> {
        crate::swap(ctx, i, j, dx, min_dy)
    }

    pub fn redeem_proportion(
        ctx: Context<RedeemShare>,
        amount: u64,
        min_redeem_amounts: Vec<u64>,
    ) -> Result<()> {
        crate::redeem_proportion(ctx, amount, min_redeem_amounts)
    }

    pub fn redeem_single(
        ctx: Context<RedeemShare>,
        amount: u64,
        i: u16,
        min_redeem_amount: u64,
    ) -> Result<()> {
        crate::redeem_single(ctx, amount, i, min_redeem_amount)
    }
}

const MINT_SEED: &[u8] = b"mint";
const HOLDER_SEED: &[u8] = b"holder";
const SOL: &[u8] = b"sol";

const INIT_SOL: u64 = 100000000u64;

/// initialize the jitoSOL pool with its fees and amplitude
pub fn initialize_pool(
    ctx: Context<InitializePool>,
    mint_fee: u64,
    swap_fee: u64,
    redeem_fee: u64,
    a: u64,
) -> Result<()> {
    let state = &mut ctx.accounts.state_account;

    if state.pool_initialized {
        return Err(errors::ErrorCode::AccountInitialized.into());
    }
    let current_epoch = Clock::get()?.epoch;
    state.authority = ctx.accounts.payer.key();
    state.mint_fee = mint_fee;
    state.swap_fee = swap_fee;
    state.redeem_fee = redeem_fee;
    state.a = a;
    state.a_block = current_epoch;
    state.future_a = a;
    state.future_a_block = current_epoch;
    state.tokens = vec![
        ctx.accounts.system_program.key(),
        ctx.accounts.jito_sol_mint_account.key(),
    ];
    state.balances = vec![0, 0];
    state.precisions = vec![1, 1];
    state.total_supply = 0;
    state.pool_initialized = true;
    state.bump = ctx.bumps.state_account;
    state.stake_pool = ctx.accounts.stake_pool_account.key();

    anchor_lang::system_program::transfer(
        CpiContext::new(
            ctx.accounts.system_program.to_account_info(),
            anchor_lang::system_program::Transfer {
                from: ctx.accounts.payer.to_account_info(),
                to: ctx.accounts.sol_program_account.to_account_info(),
            },
        ),
        INIT_SOL,
    )?;

    emit!(event::CreatePool {
        a,
        tokens: vec![
            ctx.accounts.system_program.key(),
            ctx.accounts.jito_sol_mint_account.key()
        ],
        mint_fee,
        redeem_fee,
        swap_fee,
    });
    Ok(())
}

/// initialize the jitoSOL pool token with its name, symbol, and URL
pub fn initialize_token(
    ctx: Context<InitializeToken>,
    token_name: Box<String>,
    token_symbol: Box<String>,
    token_uri: Box<String>,
) -> Result<()> {
    let state = &mut ctx.accounts.state_account;

    let jito_sol_key = ctx.accounts.jito_sol_mint_account.key();

    if state.token_initialized {
        return Err(errors::ErrorCode::AccountInitialized.into());
    }
    if state.tokens[1] != jito_sol_key {
        return Err(errors::ErrorCode::ArgumentValidationFailure.into());
    }
    if state.authority != ctx.accounts.payer.key() {
        return Err(errors::ErrorCode::Unauthorized.into());
    }

    let signer_seeds: &[&[&[u8]]] =
        &[&[MINT_SEED, jito_sol_key.as_ref(), &[ctx.bumps.mint_account]]];

    create_metadata_accounts_v3(
        CpiContext::new(
            ctx.accounts.token_metadata_program.to_account_info(),
            CreateMetadataAccountsV3 {
                metadata: ctx.accounts.metadata_account.to_account_info(),
                mint: ctx.accounts.mint_account.to_account_info(),
                mint_authority: ctx.accounts.mint_account.to_account_info(), // PDA is mint authority
                update_authority: ctx.accounts.mint_account.to_account_info(), // PDA is update authority
                payer: ctx.accounts.payer.to_account_info(),
                system_program: ctx.accounts.system_program.to_account_info(),
                rent: ctx.accounts.rent.to_account_info(),
            },
        )
        .with_signer(signer_seeds),
        DataV2 {
            name: token_name.to_string(),
            symbol: token_symbol.to_string(),
            uri: token_uri.to_string(),
            seller_fee_basis_points: 0,
            creators: None,
            collection: None,
            uses: None,
        },
        false, // Is mutable
        true,  // Update authority is signer
        None,  // Collection details
    )?;
    state.pool_mint = ctx.accounts.mint_account.key();
    state.token_initialized = true;
    Ok(())
}

/// modify the amplitude of the curve and its effective epoch
pub fn modify_a(ctx: Context<ModifyA>, a: u64, future_a_block: u64) -> Result<()> {
    let state = &mut ctx.accounts.state_account;
    if state.authority != ctx.accounts.payer.key() {
        return Err(errors::ErrorCode::Unauthorized.into());
    }
    let current_block = Clock::get()?.epoch;
    let initial_a: u64 = pool::get_a(state.a, state.a_block, state.future_a, state.future_a_block)
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;

    if initial_a > a || current_block > future_a_block {
        return Err(errors::ErrorCode::ArgumentValidationFailure.into());
    }

    state.a = initial_a;
    state.a_block = current_block;
    state.future_a = a;
    state.future_a_block = future_a_block;
    emit!(event::AModified {
        value: a,
        time: future_a_block,
    });
    Ok(())
}

/// mint the jitoSOL pool tokens with respect to the minimum mint amount
pub fn mint(ctx: Context<MintShare>, amounts: Vec<u64>, min_mint_amount: u64) -> Result<()> {
    let state = &mut ctx.accounts.state_account;
    let jito_sol_key = ctx.accounts.jito_sol_mint_account.key();

    if ctx.accounts.jito_sol_user_token_account.mint != state.tokens[1] {
        return Err(errors::ErrorCode::TokenValidationFailure.into());
    }
    if jito_sol_key != state.tokens[1] {
        return Err(errors::ErrorCode::TokenValidationFailure.into());
    }
    if ctx.accounts.stake_pool_account.key() != state.stake_pool {
        return Err(errors::ErrorCode::TokenValidationFailure.into());
    }
    collect_fees(
        &ctx.accounts.sol_program_account,
        &ctx.accounts.jito_sol_program_token_account,
        state,
        &ctx.accounts.stake_pool_account,
    )?;

    let pool::MintResult {
        mint_amount,
        fee_amount,
        balances,
        total_supply,
    } = pool::get_mint_amount(state, &amounts)?;

    let a: u64 = pool::get_a(state.a, state.a_block, state.future_a, state.future_a_block)
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    if mint_amount < min_mint_amount {
        return Err(errors::ErrorCode::MintUnderMin.into());
    }
    let token_accounts = TokenAccounts {
        token_program: ctx.accounts.token_program.to_account_info(),
        system_program: ctx.accounts.system_program.to_account_info(),
        state_account: state.to_account_info(),
        payer_account: ctx.accounts.payer.to_account_info(),
        sol_user_account: ctx.accounts.sol_user_account.to_account_info(),
        jito_sol_user_token_account: ctx.accounts.jito_sol_user_token_account.to_account_info(),
        sol_program_account: ctx.accounts.sol_program_account.to_account_info(),
        jito_sol_program_token_account: ctx
            .accounts
            .jito_sol_program_token_account
            .to_account_info(),
    };

    for (i, amount) in amounts.iter().enumerate() {
        if *amount == 0u64 {
            continue;
        }
        transfer_to_program(
            i,
            token_accounts.clone(),
            *amount,
            &ctx.accounts.stake_pool_account,
        )?;
    }

    let mint_signer_seeds: &[&[&[u8]]] =
        &[&[MINT_SEED, jito_sol_key.as_ref(), &[ctx.bumps.mint_account]]];
    anchor_spl::token::mint_to(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            MintTo {
                authority: ctx.accounts.mint_account.to_account_info(),
                to: ctx.accounts.mint_token_account.to_account_info(),
                mint: ctx.accounts.mint_account.to_account_info(),
            },
            mint_signer_seeds,
        ),
        mint_amount,
    )?;

    state.total_supply = total_supply;
    state.balances = balances;
    emit!(event::Minted {
        minter: ctx.accounts.payer.key(),
        a,
        input_amounts: amounts,
        min_output_amount: min_mint_amount,
        balances: state.balances.clone(),
        total_supply: state.total_supply,
        fee_amount,
        output_amount: mint_amount,
    });

    Ok(())
}

/// swap from/to jitoSOL with respect to its minimum output
pub fn swap(ctx: Context<SwapToken>, i: u16, j: u16, dx: u64, min_dy: u64) -> Result<()> {
    let state = &mut ctx.accounts.state_account;
    let jito_sol_key = ctx.accounts.jito_sol_mint_account.key();

    if ctx.accounts.jito_sol_user_token_account.mint != state.tokens[1] {
        return Err(errors::ErrorCode::TokenValidationFailure.into());
    }
    if jito_sol_key != state.tokens[1] {
        return Err(errors::ErrorCode::TokenValidationFailure.into());
    }
    if ctx.accounts.stake_pool_account.key() != state.stake_pool {
        return Err(errors::ErrorCode::TokenValidationFailure.into());
    }
    collect_fees(
        &ctx.accounts.sol_program_account,
        &ctx.accounts.jito_sol_program_token_account,
        state,
        &ctx.accounts.stake_pool_account,
    )?;

    let pool::SwapResult {
        dx: _,
        dy,
        y,
        balance_i,
    } = pool::get_swap_amount(state, usize::from(i), usize::from(j), dx)?;
    if y < min_dy {
        return Err(errors::ErrorCode::SwapUnderMin.into());
    }

    state.balances[usize::from(i)] = balance_i;
    state.balances[usize::from(j)] = y;

    let sol_program_seeds: &[&[&[u8]]] = &[&[
        HOLDER_SEED,
        SOL,
        jito_sol_key.as_ref(),
        &[ctx.bumps.sol_program_account],
    ]];
    let jito_sol_pub_key = ctx.accounts.jito_sol_mint_account.key();
    let jito_sol_program_seeds: &[&[&[u8]]] = &[&[
        HOLDER_SEED,
        jito_sol_pub_key.as_ref(),
        &[ctx.bumps.jito_sol_program_token_account],
    ]];
    let token_accounts = TokenAccounts {
        token_program: ctx.accounts.token_program.to_account_info(),
        system_program: ctx.accounts.system_program.to_account_info(),
        state_account: state.to_account_info(),
        payer_account: ctx.accounts.payer.to_account_info(),
        sol_user_account: ctx.accounts.sol_user_account.to_account_info(),
        jito_sol_user_token_account: ctx.accounts.jito_sol_user_token_account.to_account_info(),
        sol_program_account: ctx.accounts.sol_program_account.to_account_info(),
        jito_sol_program_token_account: ctx
            .accounts
            .jito_sol_program_token_account
            .to_account_info(),
    };
    transfer_to_program(
        usize::from(i),
        token_accounts.clone(),
        dx,
        &ctx.accounts.stake_pool_account,
    )?;
    transfer_from_program(
        usize::from(j),
        token_accounts,
        dy,
        sol_program_seeds,
        jito_sol_program_seeds,
        &ctx.accounts.stake_pool_account,
    )?;

    let a: u64 = pool::get_a(state.a, state.a_block, state.future_a, state.future_a_block)
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;

    emit!(event::TokenSwapped {
        swapper: ctx.accounts.payer.key(),
        a,
        input_asset: state.tokens[usize::from(i)],
        output_asset: state.tokens[usize::from(j)],
        input_amount: dx,
        min_output_amount: min_dy,
        balances: state.balances.clone(),
        total_supply: state.total_supply,
        output_amount: dy,
    });

    Ok(())
}

/// redeem proportionally the pool token to SOL and jitoSOL with respect to the minimum amount
pub fn redeem_proportion(
    ctx: Context<RedeemShare>,
    amount: u64,
    min_redeem_amounts: Vec<u64>,
) -> Result<()> {
    let state = &mut ctx.accounts.state_account;
    let jito_sol_key = ctx.accounts.jito_sol_mint_account.key();

    if ctx.accounts.jito_sol_user_token_account.mint != state.tokens[1] {
        return Err(errors::ErrorCode::TokenValidationFailure.into());
    }
    if jito_sol_key != state.tokens[1] {
        return Err(errors::ErrorCode::TokenValidationFailure.into());
    }
    if ctx.accounts.stake_pool_account.key() != state.stake_pool {
        return Err(errors::ErrorCode::TokenValidationFailure.into());
    }
    collect_fees(
        &ctx.accounts.sol_program_account,
        &ctx.accounts.jito_sol_program_token_account,
        state,
        &ctx.accounts.stake_pool_account,
    )?;

    let pool::RedeemProportionResult {
        amounts,
        balances,
        fee_amount,
        total_supply,
        redeem_amount,
    } = pool::get_redeem_proportion_amount(state, amount)?;

    let sol_program_seeds: &[&[&[u8]]] = &[&[
        HOLDER_SEED,
        SOL,
        jito_sol_key.as_ref(),
        &[ctx.bumps.sol_program_account],
    ]];
    let jito_sol_pub_key = ctx.accounts.jito_sol_mint_account.key();
    let jito_sol_program_seeds: &[&[&[u8]]] = &[&[
        HOLDER_SEED,
        jito_sol_pub_key.as_ref(),
        &[ctx.bumps.jito_sol_program_token_account],
    ]];
    let token_accounts = TokenAccounts {
        token_program: ctx.accounts.token_program.to_account_info(),
        system_program: ctx.accounts.system_program.to_account_info(),
        state_account: state.to_account_info(),
        payer_account: ctx.accounts.payer.to_account_info(),
        sol_user_account: ctx.accounts.sol_user_account.to_account_info(),
        jito_sol_user_token_account: ctx.accounts.jito_sol_user_token_account.to_account_info(),
        sol_program_account: ctx.accounts.sol_program_account.to_account_info(),
        jito_sol_program_token_account: ctx
            .accounts
            .jito_sol_program_token_account
            .to_account_info(),
    };
    for i in 0..amounts.len() {
        if amounts[i] < min_redeem_amounts[i] {
            return Err(errors::ErrorCode::RedeemUnderMin.into());
        }

        transfer_from_program(
            i,
            token_accounts.clone(),
            amounts[i],
            sol_program_seeds,
            jito_sol_program_seeds,
            &ctx.accounts.stake_pool_account,
        )?;
    }

    let cpi_context = CpiContext::new(
        ctx.accounts.token_program.to_account_info(),
        Burn {
            from: ctx.accounts.mint_token_account.to_account_info(),
            mint: ctx.accounts.mint_account.to_account_info(),
            authority: ctx.accounts.payer.to_account_info(),
        },
    );
    anchor_spl::token::burn(cpi_context, redeem_amount)?;

    state.total_supply = total_supply;
    state.balances = balances;

    let a: u64 = pool::get_a(state.a, state.a_block, state.future_a, state.future_a_block)
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;

    emit!(event::RedeemedProportion {
        redeemer: ctx.accounts.payer.key(),
        a,
        input_amount: amount,
        min_output_amounts: min_redeem_amounts,
        balances: state.balances.clone(),
        total_supply: state.total_supply,
        fee_amount,
        output_amounts: amounts,
    });

    Ok(())
}

/// redeem the pool token to SOL or jitoSOL with respect to the minimum amount
pub fn redeem_single(
    ctx: Context<RedeemShare>,
    amount: u64,
    i: u16,
    min_redeem_amount: u64,
) -> Result<()> {
    let state = &mut ctx.accounts.state_account;
    let jito_sol_key = ctx.accounts.jito_sol_mint_account.key();

    if ctx.accounts.jito_sol_user_token_account.mint != state.tokens[1] {
        return Err(errors::ErrorCode::TokenValidationFailure.into());
    }
    if jito_sol_key != state.tokens[1] {
        return Err(errors::ErrorCode::TokenValidationFailure.into());
    }
    if ctx.accounts.stake_pool_account.key() != state.stake_pool {
        return Err(errors::ErrorCode::TokenValidationFailure.into());
    }
    collect_fees(
        &ctx.accounts.sol_program_account,
        &ctx.accounts.jito_sol_program_token_account,
        state,
        &ctx.accounts.stake_pool_account,
    )?;

    let pool::RedeemSingleResult {
        dy,
        fee_amount,
        total_supply,
        balances,
        redeem_amount,
    } = pool::get_redeem_single_amount(state, amount, usize::from(i))?;
    if dy < min_redeem_amount {
        return Err(errors::ErrorCode::RedeemUnderMin.into());
    }

    let sol_program_seeds: &[&[&[u8]]] = &[&[
        HOLDER_SEED,
        SOL,
        jito_sol_key.as_ref(),
        &[ctx.bumps.sol_program_account],
    ]];
    let jito_sol_pub_key = ctx.accounts.jito_sol_mint_account.key();
    let jito_sol_program_seeds: &[&[&[u8]]] = &[&[
        HOLDER_SEED,
        jito_sol_pub_key.as_ref(),
        &[ctx.bumps.jito_sol_program_token_account],
    ]];
    let token_accounts = TokenAccounts {
        token_program: ctx.accounts.token_program.to_account_info(),
        system_program: ctx.accounts.system_program.to_account_info(),
        state_account: state.to_account_info(),
        payer_account: ctx.accounts.payer.to_account_info(),
        sol_user_account: ctx.accounts.sol_user_account.to_account_info(),
        jito_sol_user_token_account: ctx.accounts.jito_sol_user_token_account.to_account_info(),
        sol_program_account: ctx.accounts.sol_program_account.to_account_info(),
        jito_sol_program_token_account: ctx
            .accounts
            .jito_sol_program_token_account
            .to_account_info(),
    };

    transfer_from_program(
        usize::from(i),
        token_accounts,
        dy,
        sol_program_seeds,
        jito_sol_program_seeds,
        &ctx.accounts.stake_pool_account,
    )?;

    let cpi_context = CpiContext::new(
        ctx.accounts.token_program.to_account_info(),
        Burn {
            from: ctx.accounts.mint_token_account.to_account_info(),
            mint: ctx.accounts.mint_account.to_account_info(),
            authority: ctx.accounts.payer.to_account_info(),
        },
    );
    anchor_spl::token::burn(cpi_context, redeem_amount)?;

    let mut amounts: Vec<u64> = Vec::new();
    for idx in 0..state.balances.len() {
        if idx == usize::from(i) {
            amounts.push(dy);
        } else {
            amounts.push(0u64);
        }
    }

    state.total_supply = total_supply;
    state.balances = balances;

    let a: u64 = pool::get_a(state.a, state.a_block, state.future_a, state.future_a_block)
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;

    emit!(event::RedeemedSingle {
        redeemer: ctx.accounts.payer.key(),
        a,
        input_amount: amount,
        output_asset: state.tokens[usize::from(i)],
        min_output_amount: min_redeem_amount,
        balances: state.balances.clone(),
        total_supply: state.total_supply,
        fee_amount,
        output_amount: dy,
    });
    Ok(())
}

pub fn transfer_from_program(
    index: usize,
    token_accounts: TokenAccounts,
    amount: u64,
    sol_program_seeds: &[&[&[u8]]],
    jito_sol_program_seeds: &[&[&[u8]]],
    stake_pool: &stake::StakePool,
) -> Result<()> {
    if index == 0 {
        anchor_lang::system_program::transfer(
            CpiContext::new(
                token_accounts.system_program,
                anchor_lang::system_program::Transfer {
                    from: token_accounts.sol_program_account,
                    to: token_accounts.sol_user_account,
                },
            )
            .with_signer(sol_program_seeds),
            amount,
        )?;
    } else {
        let amount_converted = convert_balance_back_from(amount, stake_pool)?;
        anchor_spl::token::transfer(
            CpiContext::new_with_signer(
                token_accounts.token_program,
                Transfer {
                    from: token_accounts.jito_sol_program_token_account.clone(),
                    to: token_accounts.jito_sol_user_token_account,
                    authority: token_accounts.jito_sol_program_token_account,
                },
                jito_sol_program_seeds,
            ),
            amount_converted,
        )?;
    }
    Ok(())
}

pub fn transfer_to_program(
    index: usize,
    token_accounts: TokenAccounts,
    amount: u64,
    stake_pool: &stake::StakePool,
) -> Result<()> {
    if index == 0 {
        anchor_lang::system_program::transfer(
            CpiContext::new(
                token_accounts.system_program,
                anchor_lang::system_program::Transfer {
                    from: token_accounts.sol_user_account,
                    to: token_accounts.sol_program_account,
                },
            ),
            amount,
        )?;
    } else {
        let amount_converted = convert_balance_back_to(amount, stake_pool)?;
        anchor_spl::token::transfer(
            CpiContext::new(
                token_accounts.token_program,
                Transfer {
                    from: token_accounts.jito_sol_user_token_account,
                    to: token_accounts.jito_sol_program_token_account,
                    authority: token_accounts.payer_account,
                },
            ),
            amount_converted,
        )?;
    }
    Ok(())
}

/// collect fees or yields from operation
pub fn collect_fees(
    sol_account: &AccountInfo,
    jito_sol_account: &Account<TokenAccount>,
    pool_info: &mut Account<state::PoolState>,
    stake_pool: &stake::StakePool,
) -> Result<()> {
    let jito_sol_balance = convert_balance(jito_sol_account.amount, stake_pool)?;
    let balances = vec![sol_account.lamports() - INIT_SOL, jito_sol_balance];
    let a: u64 = pool::get_a(
        pool_info.a,
        pool_info.a_block,
        pool_info.future_a,
        pool_info.future_a_block,
    )
    .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    let total_supply: u64 =
        pool::get_d(&balances, a).ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    if total_supply < pool_info.total_supply {
        return Err(errors::ErrorCode::PoolImbalanced.into());
    }
    pool_info.balances = balances;
    pool_info.total_supply = total_supply;
    Ok(())
}

pub fn convert_balance(balance: u64, stake_pool: &stake::StakePool) -> Result<u64> {
    let sol_balance = stake_pool.total_lamports;
    let total_supply = stake_pool.pool_token_supply;
    let result: u128 = u128::from(balance)
        .checked_mul(u128::from(sol_balance))
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?
        .checked_div(u128::from(total_supply))
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    u64::try_from(result).map_err(|_| errors::ErrorCode::ArithmeticError.into())
}

pub fn convert_balance_back(balance: u64, stake_pool: &stake::StakePool) -> Result<u64> {
    let sol_balance = stake_pool.total_lamports;
    let total_supply = stake_pool.pool_token_supply;
    let result: u128 = u128::from(balance)
        .checked_mul(u128::from(total_supply))
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?
        .checked_div(u128::from(sol_balance))
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    u64::try_from(result).map_err(|_| errors::ErrorCode::ArithmeticError.into())
}

pub fn convert_balance_back_to(balance: u64, stake_pool: &stake::StakePool) -> Result<u64> {
    let converted = convert_balance_back(balance, stake_pool)?;
    let result: u128 = u128::from(converted)
        .checked_add(1u128)
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    u64::try_from(result).map_err(|_| errors::ErrorCode::ArithmeticError.into())
}

pub fn convert_balance_back_from(balance: u64, stake_pool: &stake::StakePool) -> Result<u64> {
    let converted = convert_balance_back(balance, stake_pool)?;
    let result: u128 = u128::from(converted)
        .checked_sub(1u128)
        .ok_or::<errors::ErrorCode>(errors::ErrorCode::ArithmeticError)?;
    u64::try_from(result).map_err(|_| errors::ErrorCode::ArithmeticError.into())
}

/// internal structure for necessary accounts to transfer SOL and jitoSOL
#[derive(Clone, Debug)]
pub struct TokenAccounts<'info> {
    pub token_program: AccountInfo<'info>,
    pub system_program: AccountInfo<'info>,
    pub state_account: AccountInfo<'info>,
    pub payer_account: AccountInfo<'info>,
    pub sol_user_account: AccountInfo<'info>,
    pub jito_sol_user_token_account: AccountInfo<'info>,
    pub sol_program_account: AccountInfo<'info>,
    pub jito_sol_program_token_account: AccountInfo<'info>,
}

/// account structure for initialize pool
#[derive(Accounts)]
pub struct InitializePool<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    /// the jitoSOL token mint
    pub jito_sol_mint_account: Box<Account<'info, Mint>>,

    /// pool state account
    #[account(
        init_if_needed,
        seeds = [state::PoolState::SEED, jito_sol_mint_account.key().as_ref()],
        bump,
        payer = payer,
        space = state::PoolState::SIZE
    )]
    pub state_account: Box<Account<'info, state::PoolState>>,

    /// pool holder of SOL
    #[account(
        mut,
        seeds = [HOLDER_SEED, SOL, jito_sol_mint_account.key().as_ref()],
        bump
    )]
    pub sol_program_account: SystemAccount<'info>,

    /// pool holder of jitoSOL
    #[account(
        init_if_needed,
        seeds = [HOLDER_SEED, jito_sol_mint_account.key().as_ref()],
        bump,
        payer = payer,
        token::mint = jito_sol_mint_account,
        token::authority = jito_sol_program_token_account,
    )]
    pub jito_sol_program_token_account: Box<Account<'info, TokenAccount>>,
    /// account of jitoSOL staking information
    pub stake_pool_account: Box<Account<'info, stake::StakePool>>,

    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

/// account structures to initialize pool token
#[derive(Accounts)]
pub struct InitializeToken<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    /// the jitoSOL token mint
    pub jito_sol_mint_account: Box<Account<'info, Mint>>,

    /// pool token mint
    #[account(
        init_if_needed,
        seeds = [MINT_SEED, jito_sol_mint_account.key().as_ref()],
        bump,
        payer = payer,
        mint::decimals = 9,
        mint::authority = mint_account.key(),
        mint::freeze_authority = mint_account.key(),

    )]
    pub mint_account: Account<'info, Mint>,

    /// state_account is the pool state account
    #[account(
        mut,
        seeds = [state::PoolState::SEED, jito_sol_mint_account.key().as_ref()],
        bump,
    )]
    pub state_account: Account<'info, state::PoolState>,

    /// CHECK: Validate address by deriving pda
    /// pool token metadata account
    #[account(
        mut,
        seeds = [b"metadata", token_metadata_program.key().as_ref(), mint_account.key().as_ref()],
        bump,
        seeds::program = token_metadata_program.key(),
    )]
    pub metadata_account: UncheckedAccount<'info>,

    pub token_program: Program<'info, Token>,
    pub token_metadata_program: Program<'info, Metadata>,
    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

/// account structures for modify amplitude of a pool
#[derive(Accounts)]
pub struct ModifyA<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    /// the jitoSOL token mint
    pub jito_sol_mint_account: Box<Account<'info, Mint>>,

    /// state_account is the pool state account
    #[account(
        mut,
        seeds = [state::PoolState::SEED, jito_sol_mint_account.key().as_ref()],
        bump,
    )]
    pub state_account: Account<'info, state::PoolState>,

    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

/// account structures for mint tokens
#[derive(Accounts)]
pub struct MintShare<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    /// pool token mint
    #[account(
        mut,
        seeds = [MINT_SEED, jito_sol_mint_account.key().as_ref()],
        bump
    )]
    pub mint_account: Account<'info, Mint>,

    /// the jitoSOL token mint
    pub jito_sol_mint_account: Account<'info, Mint>,
    /// state_account is the pool state account
    #[account(
        mut,
        seeds = [state::PoolState::SEED, jito_sol_mint_account.key().as_ref()],
        bump
    )]
    pub state_account: Account<'info, state::PoolState>,
    /// ATA for pool mint and payer
    #[account(
        init_if_needed,
        payer = payer,
        associated_token::mint = mint_account,
        associated_token::authority = payer,
    )]
    pub mint_token_account: Account<'info, TokenAccount>,
    /// SOL account of the payer
    #[account(mut)]
    pub sol_user_account: SystemAccount<'info>,
    /// jitoSOL account of the payer
    #[account(mut)]
    pub jito_sol_user_token_account: Account<'info, TokenAccount>,
    /// SOL account of the pool
    #[account(
        mut,
        seeds = [HOLDER_SEED, SOL, jito_sol_mint_account.key().as_ref()],
        bump
    )]
    pub sol_program_account: SystemAccount<'info>,
    /// jitoSOL account of the pool
    #[account(
        mut,
        seeds = [HOLDER_SEED, jito_sol_mint_account.key().as_ref()],
        bump,
        token::mint = jito_sol_mint_account,
    )]
    pub jito_sol_program_token_account: Account<'info, TokenAccount>,
    /// account of jitoSOL staking information
    pub stake_pool_account: Account<'info, stake::StakePool>,

    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
}

/// account structures for swap tokens
#[derive(Accounts)]
pub struct SwapToken<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    /// the jitoSOL token mint
    pub jito_sol_mint_account: Account<'info, Mint>,
    /// state_account is the pool state account
    #[account(
        mut,
        seeds = [state::PoolState::SEED, jito_sol_mint_account.key().as_ref()],
        bump
    )]
    pub state_account: Account<'info, state::PoolState>,

    /// SOL account of the payer
    #[account(mut)]
    pub sol_user_account: SystemAccount<'info>,
    /// jitoSOL account of the payer
    #[account(mut)]
    pub jito_sol_user_token_account: Account<'info, TokenAccount>,
    /// SOL account of the pool
    #[account(
        mut,
        seeds = [HOLDER_SEED, SOL, jito_sol_mint_account.key().as_ref()],
        bump
    )]
    pub sol_program_account: SystemAccount<'info>,
    /// jitoSOL account of the pool
    #[account(
        mut,
        seeds = [HOLDER_SEED, jito_sol_mint_account.key().as_ref()],
        bump,
        token::mint = jito_sol_mint_account,
    )]
    pub jito_sol_program_token_account: Account<'info, TokenAccount>,
    /// account of jitoSOL staking information
    pub stake_pool_account: Account<'info, stake::StakePool>,

    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
}

/// account structures for redeem pool tokens
#[derive(Accounts)]
pub struct RedeemShare<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    /// pool token mint
    #[account(
        mut,
        seeds = [MINT_SEED, jito_sol_mint_account.key().as_ref()],
        bump
    )]
    pub mint_account: Account<'info, Mint>,

    /// the jitoSOL token mint
    pub jito_sol_mint_account: Account<'info, Mint>,
    /// state_account is the pool state account
    #[account(
        mut,
        seeds = [state::PoolState::SEED, jito_sol_mint_account.key().as_ref()],
        bump
    )]
    pub state_account: Account<'info, state::PoolState>,
    /// ATA for pool mint and payer
    #[account(
        init_if_needed,
        payer = payer,
        associated_token::mint = mint_account,
        associated_token::authority = payer,
    )]
    pub mint_token_account: Account<'info, TokenAccount>,
    /// SOL account of the payer
    #[account(mut)]
    pub sol_user_account: SystemAccount<'info>,
    /// jitoSOL account of the payer
    #[account(mut)]
    pub jito_sol_user_token_account: Account<'info, TokenAccount>,
    /// SOL account of the pool
    #[account(
        mut,
        seeds = [HOLDER_SEED, SOL, jito_sol_mint_account.key().as_ref()],
        bump
    )]
    pub sol_program_account: SystemAccount<'info>,
    /// jitoSOL account of the pool
    #[account(
        mut,
        seeds = [HOLDER_SEED, jito_sol_mint_account.key().as_ref()],
        bump,
        token::mint = jito_sol_mint_account,
    )]
    pub jito_sol_program_token_account: Account<'info, TokenAccount>,
    /// account of jitoSOL staking information
    pub stake_pool_account: Account<'info, stake::StakePool>,

    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
}
