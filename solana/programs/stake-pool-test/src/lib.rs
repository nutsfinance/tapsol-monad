pub mod stake;

use crate::stake::{StakePool, StakePoolProgram};
use anchor_lang::prelude::*;

declare_id!("SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy");

#[program]
pub mod stake_pool_test {
    use super::*;

    pub fn initialize(
        ctx: Context<Initialize>,
        total_lamports: u64,
        pool_token_supply: u64,
    ) -> Result<()> {
        crate::initialize(ctx, total_lamports, pool_token_supply)
    }
}

pub fn initialize(
    ctx: Context<Initialize>,
    total_lamports: u64,
    pool_token_supply: u64,
) -> Result<()> {
    let state = &mut ctx.accounts.stake_pool_account;
    state.total_lamports = total_lamports;
    state.pool_token_supply = pool_token_supply;
    Ok(())
}
#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(
        init,
        seeds = [b"test".as_ref()],
        bump,
        payer = payer,
        space = 8 + stake::StakePool::INIT_SPACE
    )]
    pub stake_pool_account: Account<'info, StakePool>,

    pub stake_pool_program: Program<'info, StakePoolProgram>,
    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}
