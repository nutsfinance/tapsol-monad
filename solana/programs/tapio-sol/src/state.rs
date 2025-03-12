use anchor_lang::prelude::*;

#[account]
#[derive(Default, InitSpace)]
pub struct PoolState {
    /// Account with authority over this PDA.
    pub authority: Pubkey,

    pub pool_mint: Pubkey,
    pub mint_fee: u64,
    pub swap_fee: u64,
    pub redeem_fee: u64,
    pub total_supply: u64,
    pub a: u64,
    pub a_block: u64,
    pub future_a: u64,
    pub future_a_block: u64,

    #[max_len(2)]
    pub balances: Vec<u64>,
    #[max_len(2)]
    pub precisions: Vec<u64>,
    #[max_len(2)]
    pub tokens: Vec<Pubkey>,
    pub pool_initialized: bool,
    pub token_initialized: bool,
    pub stake_pool: Pubkey,

    /// The bump used to generate this account
    pub bump: u8,
}

const HEADER_SIZE: usize = 8;
impl PoolState {
    pub const SEED: &'static [u8] = b"state";
    pub const SIZE: usize = HEADER_SIZE + PoolState::INIT_SPACE;
}
