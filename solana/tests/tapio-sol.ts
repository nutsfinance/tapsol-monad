import * as anchor from "@coral-xyz/anchor";
import { AnchorError, AnchorProvider, Program } from "@coral-xyz/anchor";
import { TapioSol } from "../target/types/tapio_sol";
import { StakePoolTest } from "../target/types/stake_pool_test";

import {
  createMint,
  getAssociatedTokenAddress,
  getAssociatedTokenAddressSync,
  getOrCreateAssociatedTokenAccount,
  mintTo,
} from "@solana/spl-token";

import { Keypair, PublicKey, Signer } from "@solana/web3.js";
import { assert } from "chai";

const LAMPORTS_PER_SOL = 1000000000;
describe("tapio-sol", () => {
  // Configure the client to use the local cluster.
  anchor.setProvider(anchor.AnchorProvider.env());

  const tapioSolProgram = anchor.workspace.TapioSol as Program<TapioSol>;
  const stakeTestProgram = anchor.workspace
    .StakePoolTest as Program<StakePoolTest>;
  const MINT_SEED = "mint";
  const STATE_SEED = "state";
  const HOLDER_SEED = "holder";
  const HOLDER_SOL = "sol";
  const mintAuthSC = anchor.web3.Keypair.generate();
  const tokenPayer = anchor.web3.Keypair.generate();

  const [testState] = anchor.web3.PublicKey.findProgramAddressSync(
    [Buffer.from("test")],
    stakeTestProgram.programId,
  );
  const provider = anchor.AnchorProvider.env();
  const payer = provider.wallet as anchor.Wallet;

  before(async () => {
    await createStakePool();
  });

  it("initialized success", async () => {
    const poolAccounts = await createPool(provider, payer);
    const poolState = await tapioSolProgram.account.poolState.fetch(
      poolAccounts.state,
    );
    assert.ok(poolState.poolInitialized == true);
    assert.ok(poolState.tokenInitialized == true);
    assert.ok(poolState.authority.equals(payer.publicKey));
    assert.ok(poolState.a.eq(new anchor.BN(1000)));
    assert.ok(poolState.poolMint.equals(poolAccounts.mint));
    assert.ok(poolState.totalSupply.eq(new anchor.BN(0)));
    assert.ok(poolState.precisions[0].eq(new anchor.BN(1)));
    assert.ok(poolState.precisions[1].eq(new anchor.BN(1)));
    assert.ok(poolState.balances[0].eq(new anchor.BN(0)));
    assert.ok(poolState.balances[1].eq(new anchor.BN(0)));
    assert.ok(poolState.tokens[1].equals(poolAccounts.jitoSol));
  });

  it("initialized failure", async () => {
    const poolAccounts = await createPool(provider, payer);
    try {
      await tapioSolProgram.methods
        .initializePool(
          new anchor.BN(0),
          new anchor.BN(25000000),
          new anchor.BN(30000000),
          new anchor.BN(1000),
        )
        .accounts({
          jitoSolMintAccount: poolAccounts.jitoSol,
          stakePoolAccount: testState,
        })
        .rpc();
      assert.ok(false);
    } catch (_err) {
      assert.isTrue(_err instanceof AnchorError);
      const err: AnchorError = _err;
      const errMsg = "Account already initialized.";
      assert.strictEqual(err.error.errorMessage, errMsg);
      assert.strictEqual(err.error.errorCode.number, 6000);
    }

    try {
      await tapioSolProgram.methods
        .initializeToken("Tapio Sol", "tapSOL", "https://example.com")
        .accounts({
          jitoSolMintAccount: poolAccounts.jitoSol,
        })
        .rpc();
      assert.ok(false);
    } catch (_err) {
      assert.isTrue(_err instanceof AnchorError);
      const err: AnchorError = _err;
      const errMsg = "Account already initialized.";
      assert.strictEqual(err.error.errorMessage, errMsg);
      assert.strictEqual(err.error.errorCode.number, 6000);
    }
  });

  it("mint success", async () => {
    const poolAccounts = await createPool(provider, payer);
    await tapioSolProgram.methods
      .mint(
        [new anchor.BN(100000000), new anchor.BN(100000000)],
        new anchor.BN(0),
      )
      .accounts({
        payer: payer.publicKey,
        jitoSolUserTokenAccount: getAssociatedTokenAddressSync(
          poolAccounts.jitoSol,
          payer.publicKey,
        ),
        solUserAccount: payer.publicKey,
        jitoSolMintAccount: poolAccounts.jitoSol,
        stakePoolAccount: testState,
      })
      .rpc();
    await logBalance(
      provider,
      poolAccounts.mint,
      payer.publicKey,
      poolAccounts.jitoSol,
      poolAccounts.state,
      poolAccounts.jitoSolHolder,
      poolAccounts.solHolder,
    );

    let poolState = await tapioSolProgram.account.poolState.fetch(
      poolAccounts.state,
    );
    assert.ok(
      (await getTokenBalance(provider, poolAccounts.mint, payer.publicKey)) ==
        0.2,
    );
    assert.ok(
      (await getTokenBalance(
        provider,
        poolAccounts.jitoSol,
        payer.publicKey,
      )) == 0.909090909,
    );
    assert.ok(
      (await getTokenBalanceWithTokenAccount(
        provider,
        poolAccounts.jitoSolHolder,
      )) == 0.090909091,
    );
    assert.ok(
      (await getBalanceWithTokenAccount(provider, poolAccounts.solHolder)) ==
        0.2,
    );
    assert.ok(poolState.totalSupply.eq(new anchor.BN(200000000)));
    assert.ok(poolState.balances[0].eq(new anchor.BN(100000000)));
    assert.ok(poolState.balances[1].eq(new anchor.BN(100000000)));
  });

  it("swap success", async () => {
    const poolAccounts = await createPool(provider, payer);
    await mintInitial(poolAccounts);
    await tapioSolProgram.methods
      .swap(0, 1, new anchor.BN(1000000), new anchor.BN(0))
      .accounts({
        payer: payer.publicKey,
        jitoSolUserTokenAccount: getAssociatedTokenAddressSync(
          poolAccounts.jitoSol,
          payer.publicKey,
        ),
        solUserAccount: payer.publicKey,
        jitoSolMintAccount: poolAccounts.jitoSol,
        stakePoolAccount: testState,
      })
      .rpc();
    await logBalance(
      provider,
      poolAccounts.mint,
      payer.publicKey,
      poolAccounts.jitoSol,
      poolAccounts.state,
      poolAccounts.jitoSolHolder,
      poolAccounts.solHolder,
    );
    let poolState = await tapioSolProgram.account.poolState.fetch(
      poolAccounts.state,
    );
    assert.ok(
      (await getTokenBalance(provider, poolAccounts.mint, payer.publicKey)) ==
        0.2,
    );
    assert.ok(
      (await getTokenBalance(
        provider,
        poolAccounts.jitoSol,
        payer.publicKey,
      )) == 0.909997295,
    );
    assert.ok(
      (await getTokenBalanceWithTokenAccount(
        provider,
        poolAccounts.jitoSolHolder,
      )) == 0.090002705,
    );
    assert.ok(
      (await getBalanceWithTokenAccount(provider, poolAccounts.solHolder)) ==
        0.201,
    );
    assert.ok(poolState.totalSupply.eq(new anchor.BN(200000000)));
    assert.ok(poolState.balances[0].eq(new anchor.BN(101000000)));
    assert.ok(poolState.balances[1].eq(new anchor.BN(99000475)));

    await tapioSolProgram.methods
      .swap(1, 0, new anchor.BN(1500000), new anchor.BN(0))
      .accounts({
        payer: payer.publicKey,
        jitoSolUserTokenAccount: getAssociatedTokenAddressSync(
          poolAccounts.jitoSol,
          payer.publicKey,
        ),
        solUserAccount: payer.publicKey,
        jitoSolMintAccount: poolAccounts.jitoSol,
        stakePoolAccount: testState,
      })
      .rpc();
    await logBalance(
      provider,
      poolAccounts.mint,
      payer.publicKey,
      poolAccounts.jitoSol,
      poolAccounts.state,
      poolAccounts.jitoSolHolder,
      poolAccounts.solHolder,
    );
    poolState = await tapioSolProgram.account.poolState.fetch(
      poolAccounts.state,
    );
    assert.ok(
      (await getTokenBalance(provider, poolAccounts.mint, payer.publicKey)) ==
        0.2,
    );
    assert.ok(
      (await getTokenBalance(
        provider,
        poolAccounts.jitoSol,
        payer.publicKey,
      )) == 0.908633658,
    );
    assert.ok(
      (await getTokenBalanceWithTokenAccount(
        provider,
        poolAccounts.jitoSolHolder,
      )) == 0.091366342,
    );
    assert.ok(
      (await getBalanceWithTokenAccount(provider, poolAccounts.solHolder)) ==
        0.199503396,
    );
    assert.ok(poolState.totalSupply.eq(new anchor.BN(200002500)));
    assert.ok(poolState.balances[0].eq(new anchor.BN(99499645)));
    assert.ok(poolState.balances[1].eq(new anchor.BN(100502975)));
  });

  it("redeem proportion success", async () => {
    const poolAccounts = await createPool(provider, payer);
    await mintInitial(poolAccounts);
    await tapioSolProgram.methods
      .redeemProportion(new anchor.BN(1000000), [
        new anchor.BN(0),
        new anchor.BN(0),
      ])
      .accounts({
        payer: payer.publicKey,
        jitoSolUserTokenAccount: getAssociatedTokenAddressSync(
          poolAccounts.jitoSol,
          payer.publicKey,
        ),
        solUserAccount: payer.publicKey,
        jitoSolMintAccount: poolAccounts.jitoSol,
        stakePoolAccount: testState,
      })
      .rpc();
    await logBalance(
      provider,
      poolAccounts.mint,
      payer.publicKey,
      poolAccounts.jitoSol,
      poolAccounts.state,
      poolAccounts.jitoSolHolder,
      poolAccounts.solHolder,
    );
    const poolState = await tapioSolProgram.account.poolState.fetch(
      poolAccounts.state,
    );
    assert.ok(
      (await getTokenBalance(provider, poolAccounts.mint, payer.publicKey)) ==
        0.199003,
    );
    assert.ok(
      (await getTokenBalance(
        provider,
        poolAccounts.jitoSol,
        payer.publicKey,
      )) == 0.909544089,
    );
    assert.ok(
      (await getTokenBalanceWithTokenAccount(
        provider,
        poolAccounts.jitoSolHolder,
      )) == 0.090455911,
    );
    assert.ok(
      (await getBalanceWithTokenAccount(provider, poolAccounts.solHolder)) ==
        0.1995015,
    );
    assert.ok(poolState.totalSupply.eq(new anchor.BN(199003000)));
    assert.ok(poolState.balances[0].eq(new anchor.BN(99501500)));
    assert.ok(poolState.balances[1].eq(new anchor.BN(99501500)));
  });

  it("redeem single success", async () => {
    const poolAccounts = await createPool(provider, payer);
    await mintInitial(poolAccounts);
    await tapioSolProgram.methods
      .redeemSingle(new anchor.BN(1000000), 0, new anchor.BN(0))
      .accounts({
        payer: payer.publicKey,
        jitoSolUserTokenAccount: getAssociatedTokenAddressSync(
          poolAccounts.jitoSol,
          payer.publicKey,
        ),
        solUserAccount: payer.publicKey,
        jitoSolMintAccount: poolAccounts.jitoSol,
        stakePoolAccount: testState,
      })
      .rpc();
    await logBalance(
      provider,
      poolAccounts.mint,
      payer.publicKey,
      poolAccounts.jitoSol,
      poolAccounts.state,
      poolAccounts.jitoSolHolder,
      poolAccounts.solHolder,
    );
    let poolState = await tapioSolProgram.account.poolState.fetch(
      poolAccounts.state,
    );
    assert.ok(
      (await getTokenBalance(provider, poolAccounts.mint, payer.publicKey)) ==
        0.199003,
    );
    assert.ok(
      (await getTokenBalance(
        provider,
        poolAccounts.jitoSol,
        payer.publicKey,
      )) == 0.909090909,
    );
    assert.ok(
      (await getTokenBalanceWithTokenAccount(
        provider,
        poolAccounts.jitoSolHolder,
      )) == 0.090909091,
    );
    assert.ok(
      (await getBalanceWithTokenAccount(provider, poolAccounts.solHolder)) ==
        0.199003119,
    );
    assert.ok(poolState.totalSupply.eq(new anchor.BN(199003000)));
    assert.ok(poolState.balances[0].eq(new anchor.BN(99003118)));
    assert.ok(poolState.balances[1].eq(new anchor.BN(100000000)));

    await tapioSolProgram.methods
      .redeemSingle(new anchor.BN(1000000), 1, new anchor.BN(0))
      .accounts({
        payer: payer.publicKey,
        jitoSolUserTokenAccount: getAssociatedTokenAddressSync(
          poolAccounts.jitoSol,
          payer.publicKey,
        ),
        solUserAccount: payer.publicKey,
        jitoSolMintAccount: poolAccounts.jitoSol,
        stakePoolAccount: testState,
      })
      .rpc();
    await logBalance(
      provider,
      poolAccounts.mint,
      payer.publicKey,
      poolAccounts.jitoSol,
      poolAccounts.state,
      poolAccounts.jitoSolHolder,
      poolAccounts.solHolder,
    );
    poolState = await tapioSolProgram.account.poolState.fetch(
      poolAccounts.state,
    );
    assert.ok(
      (await getTokenBalance(provider, poolAccounts.mint, payer.publicKey)) ==
        0.198006,
    );
    assert.ok(
      (await getTokenBalance(
        provider,
        poolAccounts.jitoSol,
        payer.publicKey,
      )) == 0.909997378,
    );
    assert.ok(
      (await getTokenBalanceWithTokenAccount(
        provider,
        poolAccounts.jitoSolHolder,
      )) == 0.090002622,
    );
    assert.ok(
      (await getBalanceWithTokenAccount(provider, poolAccounts.solHolder)) ==
        0.199003119,
    );
    assert.ok(poolState.totalSupply.eq(new anchor.BN(198006000)));
    assert.ok(poolState.balances[0].eq(new anchor.BN(99003119)));
    assert.ok(poolState.balances[1].eq(new anchor.BN(99002881)));
  });

  it("mint failure", async () => {
    const poolAccounts = await createPool(provider, payer);
    try {
      await tapioSolProgram.methods
        .mint(
          [new anchor.BN(100000000), new anchor.BN(100000000)],
          new anchor.BN(1000000000),
        )
        .accounts({
          payer: payer.publicKey,
          jitoSolUserTokenAccount: getAssociatedTokenAddressSync(
            poolAccounts.jitoSol,
            payer.publicKey,
          ),
          solUserAccount: payer.publicKey,
          jitoSolMintAccount: poolAccounts.jitoSol,
          stakePoolAccount: testState,
        })
        .rpc();
      assert.ok(false);
    } catch (_err) {
      assert.isTrue(_err instanceof AnchorError);
      const err: AnchorError = _err;
      const errMsg = "Mint below minimum.";
      assert.strictEqual(err.error.errorMessage, errMsg);
      assert.strictEqual(err.error.errorCode.number, 6004);
    }
  });

  it("swap failure", async () => {
    const poolAccounts = await createPool(provider, payer);
    await mintInitial(poolAccounts);
    try {
      await tapioSolProgram.methods
        .swap(0, 1, new anchor.BN(1000000), new anchor.BN(1000000000))
        .accounts({
          payer: payer.publicKey,
          jitoSolUserTokenAccount: getAssociatedTokenAddressSync(
            poolAccounts.jitoSol,
            payer.publicKey,
          ),
          solUserAccount: payer.publicKey,
          jitoSolMintAccount: poolAccounts.jitoSol,
          stakePoolAccount: testState,
        })
        .rpc();
      assert.ok(false);
    } catch (_err) {
      assert.isTrue(_err instanceof AnchorError);
      const err: AnchorError = _err;
      const errMsg = "Swap below minimum.";
      assert.strictEqual(err.error.errorMessage, errMsg);
      assert.strictEqual(err.error.errorCode.number, 6005);
    }

    try {
      await tapioSolProgram.methods
        .swap(1, 0, new anchor.BN(1500000), new anchor.BN(1000000000))
        .accounts({
          payer: payer.publicKey,
          jitoSolUserTokenAccount: getAssociatedTokenAddressSync(
            poolAccounts.jitoSol,
            payer.publicKey,
          ),
          solUserAccount: payer.publicKey,
          jitoSolMintAccount: poolAccounts.jitoSol,
          stakePoolAccount: testState,
        })
        .rpc();
      assert.ok(false);
    } catch (_err) {
      assert.isTrue(_err instanceof AnchorError);
      const err: AnchorError = _err;
      const errMsg = "Swap below minimum.";
      assert.strictEqual(err.error.errorMessage, errMsg);
      assert.strictEqual(err.error.errorCode.number, 6005);
    }
  });

  it("redeem failure", async () => {
    const poolAccounts = await createPool(provider, payer);
    await mintInitial(poolAccounts);
    try {
      await tapioSolProgram.methods
        .redeemProportion(new anchor.BN(1000000), [
          new anchor.BN(1000000000),
          new anchor.BN(1000000000),
        ])
        .accounts({
          payer: payer.publicKey,
          jitoSolUserTokenAccount: getAssociatedTokenAddressSync(
            poolAccounts.jitoSol,
            payer.publicKey,
          ),
          solUserAccount: payer.publicKey,
          jitoSolMintAccount: poolAccounts.jitoSol,
          stakePoolAccount: testState,
        })
        .rpc();
      assert.ok(false);
    } catch (_err) {
      assert.isTrue(_err instanceof AnchorError);
      const err: AnchorError = _err;
      const errMsg = "Redeem below minimum.";
      assert.strictEqual(err.error.errorMessage, errMsg);
      assert.strictEqual(err.error.errorCode.number, 6006);
    }

    try {
      await tapioSolProgram.methods
        .redeemSingle(new anchor.BN(1000000), 0, new anchor.BN(1000000000))
        .accounts({
          payer: payer.publicKey,
          jitoSolUserTokenAccount: getAssociatedTokenAddressSync(
            poolAccounts.jitoSol,
            payer.publicKey,
          ),
          solUserAccount: payer.publicKey,
          jitoSolMintAccount: poolAccounts.jitoSol,
          stakePoolAccount: testState,
        })
        .rpc();
      assert.ok(false);
    } catch (_err) {
      assert.isTrue(_err instanceof AnchorError);
      const err: AnchorError = _err;
      const errMsg = "Redeem below minimum.";
      assert.strictEqual(err.error.errorMessage, errMsg);
      assert.strictEqual(err.error.errorCode.number, 6006);
    }

    try {
      await tapioSolProgram.methods
        .redeemSingle(new anchor.BN(1000000), 1, new anchor.BN(1000000000))
        .accounts({
          payer: payer.publicKey,
          jitoSolUserTokenAccount: getAssociatedTokenAddressSync(
            poolAccounts.jitoSol,
            payer.publicKey,
          ),
          solUserAccount: payer.publicKey,
          jitoSolMintAccount: poolAccounts.jitoSol,
          stakePoolAccount: testState,
        })
        .rpc();
      assert.ok(false);
    } catch (_err) {
      assert.isTrue(_err instanceof AnchorError);
      const err: AnchorError = _err;
      const errMsg = "Redeem below minimum.";
      assert.strictEqual(err.error.errorMessage, errMsg);
      assert.strictEqual(err.error.errorCode.number, 6006);
    }
  });

  it("modifyA too low", async () => {
    const poolAccounts = await createPool(provider, payer);
    try {
      await tapioSolProgram.methods
        .modifyA(new anchor.BN(100), new anchor.BN(10000))
        .accounts({
          jitoSolMintAccount: poolAccounts.jitoSol,
        })
        .rpc();
      assert.ok(false);
    } catch (_err) {
      assert.isTrue(_err instanceof AnchorError);
      const err: AnchorError = _err;
      const errMsg = "Argument failed validation.";
      assert.strictEqual(err.error.errorMessage, errMsg);
      assert.strictEqual(err.error.errorCode.number, 6002);
    }
  });

  it("modifyA unauthorized", async () => {
    const poolAccounts = await createPool(provider, payer);
    try {
      await tapioSolProgram.methods
        .modifyA(new anchor.BN(10000), new anchor.BN(10000))
        .accounts({
          payer: tokenPayer.publicKey,
          jitoSolMintAccount: poolAccounts.jitoSol,
        })
        .signers([tokenPayer])
        .rpc();
      assert.ok(false);
    } catch (_err) {
      assert.isTrue(_err instanceof AnchorError);
      const err: AnchorError = _err;
      const errMsg = "Unauthorized signer.";
      assert.strictEqual(err.error.errorMessage, errMsg);
      assert.strictEqual(err.error.errorCode.number, 6008);
    }
  });

  it("modifyA success", async () => {
    const poolAccounts = await createPool(provider, payer);
    await tapioSolProgram.methods
      .modifyA(new anchor.BN(10000), new anchor.BN(10000))
      .accounts({
        jitoSolMintAccount: poolAccounts.jitoSol,
      })
      .rpc();
    const poolState = await tapioSolProgram.account.poolState.fetch(
      poolAccounts.state,
    );
    assert.ok(poolState.a.eq(new anchor.BN(1000)));
    assert.ok(poolState.aBlock.eq(new anchor.BN(0)));
    assert.ok(poolState.futureA.eq(new anchor.BN(10000)));
    assert.ok(poolState.futureABlock.eq(new anchor.BN(10000)));
  });

  async function createStakePool() {
    await getSOL(provider, mintAuthSC);
    await getSOL(provider, tokenPayer);
    await stakeTestProgram.methods
      .initialize(new anchor.BN(11), new anchor.BN(10))
      .rpc();
  }

  async function createPool(
    provider: AnchorProvider,
    payer: anchor.Wallet,
  ): Promise<CreatePoolInfo> {
    const jitoSol = await createToken(provider, mintAuthSC, tokenPayer);
    const [jitoSolHolder] = anchor.web3.PublicKey.findProgramAddressSync(
      [Buffer.from(HOLDER_SEED), jitoSol.toBytes()],
      tapioSolProgram.programId,
    );

    await mintToken(
      provider,
      tokenPayer,
      jitoSol,
      mintAuthSC,
      LAMPORTS_PER_SOL,
      payer.publicKey,
    );
    const [mint] = anchor.web3.PublicKey.findProgramAddressSync(
      [Buffer.from(MINT_SEED), jitoSol.toBytes()],
      tapioSolProgram.programId,
    );

    const [state] = anchor.web3.PublicKey.findProgramAddressSync(
      [Buffer.from(STATE_SEED), jitoSol.toBytes()],
      tapioSolProgram.programId,
    );
    const [solHolder] = anchor.web3.PublicKey.findProgramAddressSync(
      [Buffer.from(HOLDER_SEED), Buffer.from(HOLDER_SOL), jitoSol.toBytes()],
      tapioSolProgram.programId,
    );

    await tapioSolProgram.methods
      .initializePool(
        new anchor.BN(0),
        new anchor.BN(25000000),
        new anchor.BN(30000000),
        new anchor.BN(1000),
      )
      .accounts({
        jitoSolMintAccount: jitoSol,
        stakePoolAccount: testState,
      })
      .rpc();
    await tapioSolProgram.methods
      .initializeToken("Tapio Sol", "tapSOL", "https://example.com")
      .accounts({
        jitoSolMintAccount: jitoSol,
      })
      .rpc();
    return new CreatePoolInfo(jitoSol, jitoSolHolder, mint, state, solHolder);
  }

  async function mintInitial(poolAccounts: CreatePoolInfo) {
    await tapioSolProgram.methods
      .mint(
        [new anchor.BN(100000000), new anchor.BN(100000000)],
        new anchor.BN(0),
      )
      .accounts({
        payer: payer.publicKey,
        jitoSolUserTokenAccount: getAssociatedTokenAddressSync(
          poolAccounts.jitoSol,
          payer.publicKey,
        ),
        solUserAccount: payer.publicKey,
        jitoSolMintAccount: poolAccounts.jitoSol,
        stakePoolAccount: testState,
      })
      .rpc();
  }

  class CreatePoolInfo {
    jitoSol: PublicKey;
    jitoSolHolder: PublicKey;
    mint: PublicKey;
    state: PublicKey;
    solHolder: PublicKey;

    constructor(
      jitoSol: PublicKey,
      jitoSolHolder: PublicKey,
      mint: PublicKey,
      state: PublicKey,
      solHolder: PublicKey,
    ) {
      this.jitoSol = jitoSol;
      this.jitoSolHolder = jitoSolHolder;
      this.mint = mint;
      this.state = state;
      this.solHolder = solHolder;
    }
  }
});

async function createToken(
  provider: AnchorProvider,
  mintAuthSC: Keypair,
  payer: Signer,
): Promise<PublicKey> {
  const decimals = 9; // Set the desired number of decimal places
  return await createMint(
    provider.connection,
    payer,
    mintAuthSC.publicKey,
    mintAuthSC.publicKey,
    decimals,
  );
}

async function mintToken(
  provider: AnchorProvider,
  payer: Signer,
  mintSC: PublicKey,
  mintAuthSC: Keypair,
  amount: bigint | number,
  person: PublicKey,
): Promise<void> {
  const person1ATA = await getOrCreateAssociatedTokenAccount(
    provider.connection,
    payer,
    mintSC,
    person,
  );

  // Top up test account with SPL
  await mintTo(
    provider.connection,
    payer,
    mintSC,
    person1ATA.address,
    mintAuthSC,
    amount,
  );
}

async function getSOL(provider: AnchorProvider, payer: Signer): Promise<void> {
  await provider.connection.confirmTransaction(
    await provider.connection.requestAirdrop(
      payer.publicKey,
      2 * LAMPORTS_PER_SOL,
    ),
  );
}

async function getTokenBalance(
  provider: AnchorProvider,
  mintSC: PublicKey,
  person: PublicKey,
): Promise<number> {
  const tokenAccount = await getAssociatedTokenAddress(mintSC, person);
  return await getTokenBalanceWithTokenAccount(provider, tokenAccount);
}

async function getTokenBalanceWithTokenAccount(
  provider: AnchorProvider,
  tokenAccount: PublicKey,
): Promise<number> {
  const info = await provider.connection.getTokenAccountBalance(tokenAccount);
  if (info.value.uiAmount == null) throw new Error("No balance found");
  return info.value.uiAmount;
}

async function getBalanceWithTokenAccount(
  provider: AnchorProvider,
  account: PublicKey,
): Promise<number> {
  const info = await provider.connection.getBalance(account);
  return info / LAMPORTS_PER_SOL;
}

async function logBalance(
  provider: AnchorProvider,
  mint: PublicKey,
  payer: PublicKey,
  jitoSol: PublicKey,
  state: PublicKey,
  jitoSolHolder: PublicKey,
  solHolder: PublicKey,
): Promise<void> {
  const program = anchor.workspace.TapioSol as Program<TapioSol>;
  console.log("payer mint: " + (await getTokenBalance(provider, mint, payer)));
  console.log(
    "payer jitoSol: " + (await getTokenBalance(provider, jitoSol, payer)),
  );
  console.log(
    "payer SOL: " + (await getBalanceWithTokenAccount(provider, payer)),
  );
  console.log(
    "pool jitoSol: " +
      (await getTokenBalanceWithTokenAccount(provider, jitoSolHolder)),
  );
  console.log(
    "pool SOL: " + (await getBalanceWithTokenAccount(provider, solHolder)),
  );
  const poolState = await program.account.poolState.fetch(state);
  console.log("pool state: " + JSON.stringify(poolState));
}
