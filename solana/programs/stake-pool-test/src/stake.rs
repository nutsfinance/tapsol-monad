use anchor_lang::prelude::*;
use std::io::Write;

#[derive(
    AnchorSerialize, AnchorDeserialize, Copy, Clone, PartialEq, Eq, Default, Debug, InitSpace,
)]
pub enum AccountType {
    /// If the account has not been initialized, the enum will be 0
    #[default]
    Uninitialized,
    /// Stake pool
    StakePool,
    /// Validator stake list
    ValidatorList,
}

/// Initialized program details.
#[derive(
    AnchorSerialize, AnchorDeserialize, Copy, Clone, PartialEq, Eq, Default, Debug, InitSpace,
)]
pub struct StakePool {
    /// Account type, must be `StakePool` currently
    pub account_type: AccountType,

    /// Manager authority, allows for updating the staker, manager, and fee
    /// account
    pub manager: Pubkey,

    /// Staker authority, allows for adding and removing validators, and
    /// managing stake distribution
    pub staker: Pubkey,

    /// Stake deposit authority
    ///
    /// If a depositor pubkey is specified on initialization, then deposits must
    /// be signed by this authority. If no deposit authority is specified,
    /// then the stake pool will default to the result of:
    /// `Pubkey::find_program_address(
    ///     &[&stake_pool_address.as_ref(), b"deposit"],
    ///     program_id,
    /// )`
    pub stake_deposit_authority: Pubkey,

    /// Stake withdrawal authority bump seed
    /// for `create_program_address(&[state::StakePool account, "withdrawal"])`
    pub stake_withdraw_bump_seed: u8,

    /// Validator stake list storage account
    pub validator_list: Pubkey,

    /// Reserve stake account, holds deactivated stake
    pub reserve_stake: Pubkey,

    /// Pool Mint
    pub pool_mint: Pubkey,

    /// Manager fee account
    pub manager_fee_account: Pubkey,

    /// Pool token program id
    pub token_program_id: Pubkey,

    /// Total stake under management.
    /// Note that if `last_update_epoch` does not match the current epoch then
    /// this field may not be accurate
    pub total_lamports: u64,

    /// Total supply of pool tokens (should always match the supply in the Pool
    /// Mint)
    pub pool_token_supply: u64,

    /// Last epoch the `total_lamports` field was updated
    pub last_update_epoch: u64,
}

impl AccountSerialize for StakePool {
    fn try_serialize<W: Write>(&self, writer: &mut W) -> Result<()> {
        if AnchorSerialize::serialize(self, writer).is_err() {
            return Err(ErrorCode::AccountDidNotSerialize.into());
        }
        Ok(())
    }
}
impl AccountDeserialize for StakePool {
    fn try_deserialize(buf: &mut &[u8]) -> Result<Self> {
        Self::try_deserialize_unchecked(buf)
    }
    fn try_deserialize_unchecked(buf: &mut &[u8]) -> Result<Self> {
        AnchorDeserialize::deserialize(buf).map_err(|_| ErrorCode::AccountDidNotDeserialize.into())
    }
}
impl anchor_lang::Discriminator for StakePool {
    const DISCRIMINATOR: [u8; 8] = [0; 8];
}

impl Owner for StakePool {
    fn owner() -> Pubkey {
        crate::ID
    }
}

#[derive(Debug, Clone)]
pub struct StakePoolProgram;

impl Id for StakePoolProgram {
    fn id() -> Pubkey {
        crate::ID
    }
}
