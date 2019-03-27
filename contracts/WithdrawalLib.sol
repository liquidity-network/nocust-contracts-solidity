/* solhint-disable func-order */

pragma solidity ^0.4.24;

import "./BimodalLib.sol";
import "./ChallengeLib.sol";
import "./SafeMath/SafeMathLib256.sol";

/*
This library contains the implementations of the first NOCUST withdrawal
procedures.
*/
library WithdrawalLib {
  using SafeMathLib256 for uint256;
  using BimodalLib for BimodalLib.Ledger;
  // EVENTS
  event WithdrawalRequest(address indexed token, address indexed requestor, uint256 amount);

  event WithdrawalConfirmation(address indexed token, address indexed requestor, uint256 amount);
  
  function initWithdrawal(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    address holder,
    uint256 eon,
    uint256 withdrawalAmount
  )
    private
    /* onlyWhenContractUnpunished() */
  {
    BimodalLib.Wallet storage entry = ledger.walletBook[token][holder];

    uint256 balance = 0;
    if (token != address(this)) {
      require(ledger.tokenToTrail[token] != 0,
        't');
      balance = token.balanceOf(this);
    } else {
      balance = address(this).balance;
    }

    require(ledger.getPendingWithdrawalsAtEon(token, eon).add(withdrawalAmount) <= balance,
      'b');

    entry.withdrawals.push(BimodalLib.Withdrawal(eon, withdrawalAmount));

    ledger.addToRunningPendingWithdrawals(token, eon, withdrawalAmount);

    ledger.appendOperationToEonAccumulator(eon, token, holder, BimodalLib.Operation.WITHDRAWAL, withdrawalAmount);

    emit WithdrawalRequest(token, holder, withdrawalAmount);
  }

  /**
   * This method can be called freely by a client to initiate a withdrawal in the
   * parent-chain that will take 2 eons to be confirmable only if the client can
   * provide a satisfying proof of exclusive allotment.
   */
  function requestWithdrawal(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    bytes32[2] checksums,
    uint64 trail,
    bytes32[] allotmentChain,
    bytes32[] membershipChain,
    uint256[] values,
    uint256[2][2] lrPassiveMark, // Left, Right
    uint256 withdrawalAmount
  )
    public
    /* payable */
    /* onlyWithConstantReimbursement(100100) */
  {
    uint256 available = lrPassiveMark[0][1].sub(lrPassiveMark[0][0]);
    uint256 eon = ledger.currentEon();

    uint256 pending = ledger.getWalletPendingWithdrawalAmountAtEon(token, msg.sender, eon);
    require(available >= withdrawalAmount.add(pending),
      'b');

    require(ChallengeLib.verifyProofOfExclusiveAccountBalanceAllotment(
      ledger,
      token,
      msg.sender,
      checksums,
      trail,
      [eon.sub(1), lrPassiveMark[1][0], lrPassiveMark[1][1]],
      allotmentChain,
      membershipChain,
      values,
      lrPassiveMark[0]),
      'p');

    initWithdrawal(ledger, token, msg.sender, eon, withdrawalAmount);
  }

  /**
   * This method can be called by a client to initiate a withdrawal in the
   * parent-chain that will take 2 eons to be confirmable only if the client
   * provides a signature from the operator authorizing the initialization of this
   * withdrawal.
   */
  function requestAuthorizedWithdrawal(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    uint256 withdrawalAmount,
    uint256 expiry,
    bytes32 r, bytes32 s, uint8 v
  )
    public
  {
    requestDelegatedWithdrawal(ledger, token, msg.sender, withdrawalAmount, expiry, r, s, v);
  }

  /**
   * This method can be called by the operator to initiate a withdrawal in the
   * parent-chain that will take 2 eons to be confirmable only if the operator
   * provides a signature from the client authorizing the delegation of this
   * withdrawal initialization.
   */
  function requestDelegatedWithdrawal(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    address holder,
    uint256 withdrawalAmount,
    uint256 expiry,
    bytes32 r, bytes32 s, uint8 v
  )
    public
    /* onlyOperator() */
  {
    require(block.number <= expiry);

    uint256 eon = ledger.currentEon();
    uint256 pending = ledger.getWalletPendingWithdrawalAmountAtEon(token, holder, eon);

    require(ChallengeLib.verifyWithdrawalAuthorization(
      token,
      holder,
      expiry,
      withdrawalAmount.add(pending),
      holder,
      r, s, v));

    initWithdrawal(ledger, token, holder, eon, withdrawalAmount);
  }
  
  /**
   * This method can be called to confirm the withdrawals of a recipient that have
   * been pending for at least two eons when the operator is not halted.
   */
  function confirmWithdrawal(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    address recipient
  )
    public
    /* onlyWhenContractUnpunished() */
    returns (uint256 amount)
  {
    BimodalLib.Wallet storage entry = ledger.walletBook[token][recipient];
    BimodalLib.Withdrawal[] storage withdrawals = entry.withdrawals;

    uint256 eon = ledger.currentEon();
    amount = 0;

    /**
     * after the loop, i is set to the index of the first pending withdrawals
     * amount is the amount to be sent to the recipient
     */
    uint32 i = 0;
    for (i = 0; i < withdrawals.length; i++) {
      BimodalLib.Withdrawal storage withdrawal = withdrawals[i];
      if (withdrawal.eon.add(1) >= eon) {
        break;
      } else if (withdrawal.eon.add(2) == eon && ledger.currentEra() < ledger.EXTENDED_BLOCKS_PER_EPOCH) {
        break;
      }

      amount = amount.add(withdrawal.amount);
    }

    // set withdrawals to contain only pending withdrawal requests
    for (uint32 j = 0; j < i && i < withdrawals.length; j++) {
      withdrawals[j] = withdrawals[i];
      i++;
    }
    withdrawals.length = withdrawals.length.sub(j);

    ledger.deductFromRunningPendingWithdrawals(token, eon, eon, amount);

    BimodalLib.AmountAggregate storage eonWithdrawals = ledger.confirmedWithdrawals[token][eon.mod(ledger.EONS_KEPT)];
    BimodalLib.addToAggregate(eonWithdrawals, eon, amount);

    emit WithdrawalConfirmation(token, recipient, amount);

    // if token is not chain native asset
    if (token != address(this)) {
      require(ledger.tokenToTrail[token] != 0);
      require(token.transfer(recipient, amount));
    } else {
      recipient.transfer(amount);
    }
  }
}
