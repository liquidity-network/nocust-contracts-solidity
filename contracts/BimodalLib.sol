pragma solidity ^0.4.24;

import "./ERC20.sol";
import "./SafeMath/SafeMathLib256.sol";

/**
 * This library defines the bi-modal commit-chain ledger. It provides data
 * structure definitions, accessors and mutators.
 */
library BimodalLib {
  using SafeMathLib256 for uint256;

  // ENUMS
  enum ChallengeType {
    NONE,
    STATE_UPDATE,
    TRANSFER_DELIVERY,
    SWAP_ENACTMENT
  }

  // DATA MODELS
  /**
   * Aggregate field datastructure used to sum up deposits / withdrawals for an eon.
   */
  struct AmountAggregate {
    uint256 eon;
    uint256 amount;
  }

  /**
   * The structure for a submitted commit-chain checkpoint.
   */
  struct Checkpoint {
    uint256 eonNumber;
    bytes32 merkleRoot;
    uint256 liveChallenges;
  }

  /**
   * A structure representing a single commit-chain wallet.
   */
  struct Wallet {
    // Deposits performed in the last three eons
    AmountAggregate[3] depositsKept;
    // Withdrawals requested and not yet confirmed
    Withdrawal[] withdrawals;
    // Recovery flag denoting whether this account has retrieved its funds
    bool recovered;
  }

  /**
   * A structure denoting a single withdrawal request.
   */
  struct Withdrawal {
    uint256 eon;
    uint256 amount;
  }

  /**
   * A structure containing the information of a single challenge.
   */
  struct Challenge {
    // State Update Challenges
    ChallengeType challengeType; // 0
    uint256 block; // 1
    uint256 initialStateEon; // 2
    uint256 initialStateBalance; // 3
    uint256 deltaHighestSpendings; // 4
    uint256 deltaHighestGains; // 5
    uint256 finalStateBalance; // 6
    uint256 deliveredTxNonce; // 7
    uint64 trailIdentifier; // 8
  }

  /**
   * The types of parent-chain operations logged into the accumulator.
   */
  enum Operation {
    DEPOSIT,
    WITHDRAWAL,
    CANCELLATION
  }

  /* solhint-disable var-name-mixedcase */
  /**
   * The structure for an instance of the commit-chain ledger.
   */
  struct Ledger {
    // OPERATIONAL CONSTANTS
    uint8 EONS_KEPT;
    uint8 DEPOSITS_KEPT;
    uint256 MIN_CHALLENGE_GAS_COST;
    uint256 BLOCKS_PER_EON;
    uint256 BLOCKS_PER_EPOCH;
    uint256 EXTENDED_BLOCKS_PER_EPOCH;
    // STATE VARIABLES
    uint256 genesis;
    address operator;
    Checkpoint[5] checkpoints;
    bytes32[5] parentChainAccumulator; // bytes32[EONS_KEPT]
    uint256 lastSubmissionEon;
    mapping (address => mapping (address => mapping (address => Challenge))) challengeBook;
    mapping (address => mapping (address => Wallet)) walletBook;
    mapping (address => AmountAggregate[5]) deposits;
    mapping (address => AmountAggregate[5]) pendingWithdrawals;
    mapping (address => AmountAggregate[5]) confirmedWithdrawals;
    mapping (address => uint64) tokenToTrail;
    address[] trailToToken;
  }
  /* solhint-enable */

  // INITIALIZATION
  function init(
    Ledger storage self,
    uint256 blocksPerEon,
    address operator
  )
    public
  {
    self.BLOCKS_PER_EON = blocksPerEon;
    self.BLOCKS_PER_EPOCH = self.BLOCKS_PER_EON.div(4);
    self.EXTENDED_BLOCKS_PER_EPOCH = self.BLOCKS_PER_EON.div(3);
    self.EONS_KEPT = 5; // eons kept on chain
    self.DEPOSITS_KEPT = 3; // deposit aggregates kept on chain
    self.MIN_CHALLENGE_GAS_COST = 0.005 szabo; // 5 gwei minimum gas reimbursement cost
    self.operator = operator;
    self.genesis = block.number;
  }

  // DATA ACCESS
  /**
   * This method calculates the current eon number using the genesis block number
   * and eon duration.
   */
  function currentEon(
    Ledger storage self
  )
    public
    view
    returns (uint256)
  {
    return block.number.sub(self.genesis).div(self.BLOCKS_PER_EON).add(1);
  }

  /**
   * This method calculates the current era number
   */
  function currentEra(
    Ledger storage self
  )
    public
    view
    returns (uint256)
  {
    return block.number.sub(self.genesis).mod(self.BLOCKS_PER_EON);
  }

  /**
   * This method is used to embed a parent-chain operation into the accumulator
   * through hashing its values. The on-chain accumulator is used to provide a
   * reference with respect to which the operator can commit checkpoints.
   */
  function appendOperationToEonAccumulator(
    Ledger storage self,
    uint256 eon,
    ERC20 token,
    address participant,
    Operation operation,
    uint256 value
  )
    public
  {
    self.parentChainAccumulator[eon.mod(self.EONS_KEPT)] = keccak256(abi.encodePacked(
      self.parentChainAccumulator[eon.mod(self.EONS_KEPT)],
      eon,
      token,
      participant,
      operation,
      value));
  }

  /**
   * Retrieves the total pending withdrawal amount at a specific eon.
   */
  function getPendingWithdrawalsAtEon(
    Ledger storage self,
    ERC20 token,
    uint256 eon
  )
    public
    view
    returns (uint256)
  {
    uint256 lastAggregateEon = 0;
    for (uint256 i = 0; i < self.EONS_KEPT; i++) {
      AmountAggregate storage currentAggregate = self.pendingWithdrawals[token][eon.mod(self.EONS_KEPT)];
      if (currentAggregate.eon == eon) {
        return currentAggregate.amount;
      } else if (currentAggregate.eon > lastAggregateEon && currentAggregate.eon < eon) {
        // As this is a running aggregate value, if the target eon value is not set,
        // the most recent value is provided and assumed to have remained constant.
        lastAggregateEon = currentAggregate.eon;
      }
      if (eon == 0) {
        break;
      }
      eon = eon.sub(1);
    }
    if (lastAggregateEon == 0) {
      return 0;
    }
    return self.pendingWithdrawals[token][lastAggregateEon.mod(self.EONS_KEPT)].amount;
  }

  /**
   * Increases the total pending withdrawal amount at a specific eon.
   */
  function addToRunningPendingWithdrawals(
    Ledger storage self,
    ERC20 token,
    uint256 eon,
    uint256 value
  )
    public
  {
    AmountAggregate storage aggregate = self.pendingWithdrawals[token][eon.mod(self.EONS_KEPT)];
    // As this is a running aggregate, the target eon and all those that
    // come after it are updated to reflect the increase.
    if (aggregate.eon < eon) { // implies eon > 0
      aggregate.amount = getPendingWithdrawalsAtEon(self, token, eon.sub(1)).add(value);
      aggregate.eon = eon;
    } else {
      aggregate.amount = aggregate.amount.add(value);
    }
  }
  
  /**
   * Decreases the total pending withdrawal amount at a specific eon.
   */
  function deductFromRunningPendingWithdrawals(
    Ledger storage self,
    ERC20 token,
    uint256 eon,
    uint256 latestEon,
    uint256 value
  )
    public
  {
    /* Initalize empty aggregates to running values */
    for (uint256 i = 0; i < self.EONS_KEPT; i++) {
      uint256 targetEon = eon.add(i);
      AmountAggregate storage aggregate = self.pendingWithdrawals[token][targetEon.mod(self.EONS_KEPT)];
      if (targetEon > latestEon) {
        break;
      } else if (aggregate.eon < targetEon) { // implies targetEon > 0
        // Set constant running value
        aggregate.eon = targetEon;
        aggregate.amount = getPendingWithdrawalsAtEon(self, token, targetEon.sub(1));
      }
    }
    /* Update running values */
    for (i = 0; i < self.EONS_KEPT; i++) {
      targetEon = eon.add(i);
      aggregate = self.pendingWithdrawals[token][targetEon.mod(self.EONS_KEPT)];
      if (targetEon > latestEon) {
        break;
      } else if (aggregate.eon < targetEon) {
        revert('X'); // This is impossible.
      } else {
        aggregate.amount = aggregate.amount.sub(value);
      }
    }
  }

  /**
   * Get the total number of live challenges for a specific eon.
   */
  function getLiveChallenges(
    Ledger storage self,
    uint256 eon
  )
    public
    view
    returns (uint)
  {
    Checkpoint storage checkpoint = self.checkpoints[eon.mod(self.EONS_KEPT)];
    if (checkpoint.eonNumber != eon) {
      return 0;
    }
    return checkpoint.liveChallenges;
  }

  /**
   * Get checkpoint data or assume it to be empty if non-existant.
   */
  function getOrCreateCheckpoint(
    Ledger storage self,
    uint256 targetEon,
    uint256 latestEon
  )
    public
    returns (Checkpoint storage checkpoint)
  {
    require(latestEon < targetEon.add(self.EONS_KEPT) && targetEon <= latestEon);

    uint256 index = targetEon.mod(self.EONS_KEPT);
    checkpoint = self.checkpoints[index];

    if (checkpoint.eonNumber != targetEon) {
      checkpoint.eonNumber = targetEon;
      checkpoint.merkleRoot = bytes32(0);
      checkpoint.liveChallenges = 0;
    }

    return checkpoint;
  }

  /**
   * Get the total amount pending withdrawal by a wallet at a specific eon.
   */
  function getWalletPendingWithdrawalAmountAtEon(
    Ledger storage self,
    ERC20 token,
    address holder,
    uint256 eon
  )
    public
    view
    returns (uint256 amount)
  {
    amount = 0;

    Wallet storage accountingEntry = self.walletBook[token][holder];
    Withdrawal[] storage withdrawals = accountingEntry.withdrawals;
    for (uint32 i = 0; i < withdrawals.length; i++) {
      Withdrawal storage withdrawal = withdrawals[i];
      if (withdrawal.eon == eon) {
        amount = amount.add(withdrawal.amount);
      } else if (withdrawal.eon > eon) {
        break;
      }
    }
  }

  /**
   * Get the total amounts deposited and pending withdrawal at the current eon.
   */
  function getCurrentEonDepositsWithdrawals(
    Ledger storage self,
    ERC20 token,
    address holder
  )
    public
    view
    returns (uint256 currentEonDeposits, uint256 currentEonWithdrawals)
  {

    currentEonDeposits = 0;
    currentEonWithdrawals = 0;

    Wallet storage accountingEntry = self.walletBook[token][holder];
    Challenge storage challengeEntry = self.challengeBook[token][holder][holder];

    AmountAggregate storage depositEntry =
      accountingEntry.depositsKept[challengeEntry.initialStateEon.mod(self.DEPOSITS_KEPT)];

    if (depositEntry.eon == challengeEntry.initialStateEon) {
      currentEonDeposits = currentEonDeposits.add(depositEntry.amount);
    }

    currentEonWithdrawals = getWalletPendingWithdrawalAmountAtEon(self, token, holder, challengeEntry.initialStateEon);

    return (currentEonDeposits, currentEonWithdrawals);
  }

  // UTILITY
  function addToAggregate(
    AmountAggregate storage aggregate,
    uint256 eon,
    uint256 value
  )
    public
  {
    if (eon > aggregate.eon) {
      aggregate.eon = eon;
      aggregate.amount = value;
    } else {
      aggregate.amount = aggregate.amount.add(value);
    }
  }

  function clearAggregate(
    AmountAggregate storage aggregate
  )
    public
  {
    aggregate.eon = 0;
    aggregate.amount = 0;
  }

  function signedMessageECRECOVER(
    bytes32 message,
    bytes32 r, bytes32 s, uint8 v
  )
    public
    pure
    returns (address)
  {
    return ecrecover(
      keccak256(abi.encodePacked(
        "\x19Ethereum Signed Message:\n32",
        keccak256(abi.encodePacked(
          "\x19Liquidity.Network Authorization:\n32",
          message)))),
      v, r, s);
  }
}
