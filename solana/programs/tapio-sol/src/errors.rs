use anchor_lang::prelude::*;
#[error_code]
pub enum ErrorCode {
    #[msg("Account already initialized.")]
    AccountInitialized,

    #[msg("Encountered an arithmetic under/overflow error.")]
    ArithmeticError,

    #[msg("Argument failed validation.")]
    ArgumentValidationFailure,

    #[msg("Token failed validation.")]
    TokenValidationFailure,

    #[msg("Mint below minimum.")]
    MintUnderMin,

    #[msg("Swap below minimum.")]
    SwapUnderMin,

    #[msg("Redeem below minimum.")]
    RedeemUnderMin,

    #[msg("Pool imbalanced.")]
    PoolImbalanced,

    #[msg("Unauthorized signer.")]
    Unauthorized,
}
