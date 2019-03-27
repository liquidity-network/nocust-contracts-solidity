pragma solidity ^0.4.24;

import "./BimodalProxy.sol";
import "./ERC20.sol";
import "./WithdrawalLib.sol";
import "./SafeMath/SafeMathLib256.sol";

contract WithdrawalProxy is BimodalProxy {
  using SafeMathLib256 for uint256;

  modifier onlyWithConstantReimbursement(uint256 responseGas) {
    require(
      msg.value >= responseGas.mul(ledger.MIN_CHALLENGE_GAS_COST) &&
      msg.value >= responseGas.mul(tx.gasprice),
      'r');
    ledger.operator.transfer(msg.value);
    _;
  }

  // =========================================================================
  function requestWithdrawal(
    ERC20 token,
    bytes32[2] checksums,
    uint64 trail,
    bytes32[] allotmentChain,
    bytes32[] membershipChain,
    uint256[] values,
    uint256[2][2] lrPassiveMark,
    uint256 withdrawalAmount
  )
    public
    payable
    onlyWithConstantReimbursement(100100)
    onlyWhenContractUnpunished()
  {
    WithdrawalLib.requestWithdrawal(
      ledger,
      token,
      checksums,
      trail,
      allotmentChain,
      membershipChain,
      values,
      lrPassiveMark,
      withdrawalAmount);
  }

  function requestAuthorizedWithdrawal(
    ERC20 token,
    uint256 withdrawalAmount,
    uint256 expiry,
    bytes32 r, bytes32 s, uint8 v
  )
    public
    onlyWhenContractUnpunished()
  {
    WithdrawalLib.requestAuthorizedWithdrawal(
      ledger,
      token,
      withdrawalAmount,
      expiry,
      r,
      s,
      v);
  }

  function requestDelegatedWithdrawal(
    ERC20 token,
    address holder,
    uint256 withdrawalAmount,
    uint256 expiry,
    bytes32 r, bytes32 s, uint8 v
  )
    public
    onlyOperator()
    onlyWhenContractUnpunished()
  {
    WithdrawalLib.requestDelegatedWithdrawal(
      ledger,
      token,
      holder,
      withdrawalAmount,
      expiry,
      r,
      s,
      v);
  }

  function confirmWithdrawal(
    ERC20 token,
    address recipient
  )
    public
    onlyWhenContractUnpunished()
    returns (uint256)
  {
    return WithdrawalLib.confirmWithdrawal(
      ledger,
      token,
      recipient);
  }
}
