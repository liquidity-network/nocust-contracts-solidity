pragma solidity ^0.4.24;

import "./ERC20.sol";
import "./BimodalLib.sol";
import "./SafeMath/SafeMathLib256.sol";

contract BimodalProxy {
  using SafeMathLib256 for uint256;
  using BimodalLib for BimodalLib.Ledger;

  // EVENTS
  event CheckpointSubmission(uint256 indexed eon, bytes32 merkleRoot);
  
  event Deposit(address indexed token, address indexed recipient, uint256 amount);
  
  event WithdrawalRequest(address indexed token, address indexed requestor, uint256 amount);
  
  event WithdrawalConfirmation(address indexed token, address indexed requestor, uint256 amount);
  
  event ChallengeIssued(address indexed token, address indexed recipient, address indexed sender);
  
  event StateUpdate(
    address indexed token,
    address indexed account,
    uint256 indexed eon,
    uint64 trail,
    bytes32[] allotmentChain,
    bytes32[] membershipChain,
    uint256[] values,
    uint256[2][3] lrDeltasPassiveMark,
    bytes32 activeStateChecksum,
    bytes32 passiveChecksum,
    bytes32 r, bytes32 s, uint8 v);
  
  // BIMODAL LEDGER DATA
  BimodalLib.Ledger internal ledger;
  
  // INITIALIZATION
  constructor(
    uint256 blocksPerEon,
    address operator
  )
    public
  {
    ledger.init(blocksPerEon, operator);
  }

  // SAFETY MODIFIERS
  modifier onlyOperator() {
    require(msg.sender == ledger.operator);
    _;
  }

  modifier onlyWhenContractUnpunished() {
    require(
      !hasOutstandingChallenges() && !hasMissedCheckpointSubmission(),
      'p');
    _;
  }

  // PUBLIC DATA EXPOSURE
  function getClientContractStateVariables(
    ERC20 token,
    address holder
  )
    public
    view
    returns (
      uint256 latestCheckpointEonNumber,
      bytes32[5] latestCheckpointsMerkleRoots,
      uint256[5] latestCheckpointsLiveChallenges,
      uint256 currentEonDeposits,
      uint256 previousEonDeposits,
      uint256 secondPreviousEonDeposits,
      uint256[2][] pendingWithdrawals,
      uint256 holderBalance
    )
  {
    latestCheckpointEonNumber = ledger.lastSubmissionEon;
    for (uint32 i = 0; i < ledger.EONS_KEPT && i < ledger.currentEon(); i++) {
      BimodalLib.Checkpoint storage checkpoint =
        ledger.checkpoints[ledger.lastSubmissionEon.sub(i).mod(ledger.EONS_KEPT)];
      latestCheckpointsMerkleRoots[i] = checkpoint.merkleRoot;
      latestCheckpointsLiveChallenges[i] = checkpoint.liveChallenges;
    }

    holderBalance = ledger.currentEon();
    currentEonDeposits = getDepositsAtEon(token, holder, holderBalance);
    if (holderBalance > 1) {
      previousEonDeposits = getDepositsAtEon(token, holder, holderBalance - 1);
    }
    if (holderBalance > 2) {
      secondPreviousEonDeposits = getDepositsAtEon(token, holder, holderBalance - 2);
    }
    BimodalLib.Wallet storage wallet = ledger.walletBook[token][holder];
    pendingWithdrawals = new uint256[2][](wallet.withdrawals.length);
    for (i = 0; i < wallet.withdrawals.length; i++) {
      BimodalLib.Withdrawal storage withdrawal = wallet.withdrawals[i];
      pendingWithdrawals[i] = [withdrawal.eon, withdrawal.amount];
    }
    holderBalance = token != address(this) ? token.balanceOf(holder) : holder.balance;
  }

  function getServerContractStateVariables()
    public
    view
    returns (
      bytes32 parentChainAccumulator,
      uint256 lastSubmissionEon,
      bytes32 lastCheckpointRoot,
      bool isCheckpointSubmitted,
      bool missedCheckpointSubmission,
      uint256 liveChallenges
    )
  {
    uint256 currentEon = ledger.currentEon();
    parentChainAccumulator = getParentChainAccumulatorAtSlot(uint8(currentEon.mod(ledger.EONS_KEPT)));

    BimodalLib.Checkpoint storage lastCheckpoint = ledger.checkpoints[ledger.lastSubmissionEon.mod(ledger.EONS_KEPT)];
    lastSubmissionEon = ledger.lastSubmissionEon;
    lastCheckpointRoot = lastCheckpoint.merkleRoot;

    isCheckpointSubmitted = lastSubmissionEon == currentEon;
    missedCheckpointSubmission = hasMissedCheckpointSubmission();

    liveChallenges = getLiveChallenges(currentEon);
  }

  function getServerContractLedgerStateVariables(
    uint256 eonNumber,
    ERC20 token
  )
    public
    view
    returns (
      uint256 pendingWithdrawals,
      uint256 confirmedWithdrawals,
      uint256 deposits,
      uint256 totalBalance
    )
  {
    uint8 eonSlot = uint8(eonNumber.mod(ledger.EONS_KEPT));
    uint256 targetEon = 0;
    (targetEon, pendingWithdrawals) = getPendingWithdrawalsAtSlot(token, eonSlot);
    if (targetEon != eonNumber) {
      pendingWithdrawals = 0;
    }
    (targetEon, confirmedWithdrawals) = getConfirmedWithdrawalsAtSlot(token, eonSlot);
    if (targetEon != eonNumber) {
      confirmedWithdrawals = 0;
    }
    (targetEon, deposits) = getDepositsAtSlot(token, eonSlot);
    if (targetEon != eonNumber) {
      deposits = 0;
    }
    // totalBalance is for current state and not for eonNumber, which is stange
    totalBalance = token != address(this) ? token.balanceOf(this) : address(this).balance;
  }

  function hasOutstandingChallenges()
    public
    view
    returns (bool)
  {
    return ledger.getLiveChallenges(ledger.currentEon().sub(1)) > 0
      && ledger.currentEra() > ledger.BLOCKS_PER_EPOCH;
  }

  function hasMissedCheckpointSubmission()
    public
    view
    returns (bool)
  {
    return ledger.currentEon().sub(ledger.lastSubmissionEon) > 1;
  }

  function getCheckpointAtSlot(
    uint8 slot
  )
    public
    view
    returns (
      uint256,
      bytes32,
      uint256
    )
  {
    BimodalLib.Checkpoint storage checkpoint = ledger.checkpoints[slot];
    return (
      checkpoint.eonNumber,
      checkpoint.merkleRoot,
      checkpoint.liveChallenges
    );
  }

  function getParentChainAccumulatorAtSlot(
    uint8 slot
  )
    public
    view
    returns (bytes32)
  {
    return ledger.parentChainAccumulator[slot];
  }

  function getChallenge(
    ERC20 token,
    address sender,
    address recipient
  )
    public
    view
    returns (
      BimodalLib.ChallengeType,
      uint256,
      uint,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint64
    )
  {
    BimodalLib.Challenge storage challenge = ledger.challengeBook[token][recipient][sender];
    return (
      challenge.challengeType,
      challenge.block,
      challenge.initialStateEon,
      challenge.initialStateBalance,
      challenge.deltaHighestSpendings,
      challenge.deltaHighestGains,
      challenge.finalStateBalance,
      challenge.deliveredTxNonce,
      challenge.trailIdentifier);
  }

  function getIsWalletRecovered(
    ERC20 token,
    address holder
  )
    public
    view
    returns (
      bool
    )
  {
    BimodalLib.Wallet storage wallet = ledger.walletBook[token][holder];
    return (
        wallet.recovered);
  }

  function getDepositsAtEon(
    ERC20 token,
    address addr,
    uint256 eon
  )
    public
    view
    returns (uint256)
  {
    (uint256 aggregateEon, uint256 aggregateAmount) =
      getWalletDepositAggregateAtSlot(token, addr, uint8(eon.mod(ledger.DEPOSITS_KEPT)));
    return aggregateEon == eon ? aggregateAmount : 0;
  }

  function getDepositsAtSlot(
    ERC20 token,
    uint8 slot
  )
    public
    view
    returns (uint, uint)
  {
    BimodalLib.AmountAggregate storage aggregate = ledger.deposits[token][slot];
    return (
      aggregate.eon,
      aggregate.amount);
  }

  function getWalletDepositAggregateAtSlot(
    ERC20 token,
    address addr,
    uint8 slot
  )
    public
    view
    returns (uint, uint)
  {
    BimodalLib.AmountAggregate memory deposit = ledger.walletBook[token][addr].depositsKept[slot];
    return (
      deposit.eon,
      deposit.amount);
  }

  function getPendingWithdrawalsAtEon(
    ERC20 token,
    uint256 eon
  )
    public
    view
    returns (uint)
  {
    return ledger.getPendingWithdrawalsAtEon(token, eon);
  }

  function getPendingWithdrawalsAtSlot(
    ERC20 token,
    uint8 slot
  )
    public
    view
    returns (uint, uint)
  {
    BimodalLib.AmountAggregate storage aggregate = ledger.pendingWithdrawals[token][slot];
    return (
      aggregate.eon,
      aggregate.amount);
  }

  function getConfirmedWithdrawalsAtSlot(
    ERC20 token,
    uint8 slot
  )
    public
    view
    returns (uint, uint)
  {
    BimodalLib.AmountAggregate storage aggregate = ledger.confirmedWithdrawals[token][slot];
    return (
      aggregate.eon,
      aggregate.amount);
  }

  function getWalletPendingWithdrawalAmountAtEon(
    ERC20 token,
    address holder,
    uint256 eon
  )
    public
    view
    returns (uint256)
  {
    return ledger.getWalletPendingWithdrawalAmountAtEon(token, holder, eon);
  }

  function getTokenTrail(
    ERC20 token
  )
    public
    view
    returns (uint64)
  {
    return ledger.tokenToTrail[token];
  }

  function getTokenAtTrail(
    uint64 trail
  )
    public
    view
    returns (address)
  {
    return ledger.trailToToken[trail];
  }

  function getCurrentEonDepositsWithdrawals(
    ERC20 token,
    address holder
  )
    public
    view
    returns (uint256 currentEonDeposits, uint256 currentEonWithdrawals)
  {
    return ledger.getCurrentEonDepositsWithdrawals(token, holder);
  }

  function EONS_KEPT() // solhint-disable-line func-name-mixedcase
    public
    view
    returns (uint8)
  {
    return ledger.EONS_KEPT;
  }

  function DEPOSITS_KEPT() // solhint-disable-line func-name-mixedcase
    public
    view
    returns (uint8)
  {
    return ledger.DEPOSITS_KEPT;
  }

  function MIN_CHALLENGE_GAS_COST() // solhint-disable-line func-name-mixedcase
    public
    view
    returns (uint)
  {
    return ledger.MIN_CHALLENGE_GAS_COST;
  }

  function BLOCKS_PER_EON() // solhint-disable-line func-name-mixedcase
    public
    view
    returns (uint)
  {
    return ledger.BLOCKS_PER_EON;
  }

  function BLOCKS_PER_EPOCH() // solhint-disable-line func-name-mixedcase
    public
    view
    returns (uint)
  {
    return ledger.BLOCKS_PER_EPOCH;
  }

  function EXTENDED_BLOCKS_PER_EPOCH() // solhint-disable-line func-name-mixedcase
    public
    view
    returns (uint)
  {
    return ledger.EXTENDED_BLOCKS_PER_EPOCH;
  }

  function genesis()
    public
    view
    returns (uint)
  {
    return ledger.genesis;
  }

  function operator()
    public
    view
    returns (address)
  {
    return ledger.operator;
  }

  function lastSubmissionEon()
    public
    view
    returns (uint)
  {
    return ledger.lastSubmissionEon;
  }

  function currentEon()
    public
    view
    returns (uint)
  {
    return ledger.currentEon();
  }

  function currentEra()
    public
    view
    returns (uint)
  {
    return ledger.currentEra();
  }

  function getLiveChallenges(uint256 eon)
    public
    view
    returns (uint)
  {
    BimodalLib.Checkpoint storage checkpoint = ledger.checkpoints[eon.mod(ledger.EONS_KEPT)];
    if (checkpoint.eonNumber != eon) {
      return 0;
    }
    return checkpoint.liveChallenges;
  }

  function signedMessageECRECOVER(
    bytes32 message,
    bytes32 r, bytes32 s, uint8 v
  )
    public
    pure
    returns (address)
  {
    return BimodalLib.signedMessageECRECOVER(message, r, s, v);
  }
}
