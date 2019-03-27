pragma solidity ^0.4.24;

import "./BimodalProxy.sol";
import "./ERC20.sol";
import "./RecoveryLib.sol";
import "./SafeMath/SafeMathLib256.sol";

contract RecoveryProxy is BimodalProxy {
  using SafeMathLib256 for uint256;

  modifier onlyWhenContractPunished() {
    require(
      hasOutstandingChallenges() || hasMissedCheckpointSubmission(),
      'f');
    _;
  }

  // =========================================================================
  function recoverOnlyParentChainFunds(
    ERC20 token,
    address holder
  )
    public
    onlyWhenContractPunished()
    returns (uint256 reclaimed)
  {
    reclaimed = RecoveryLib.recoverOnlyParentChainFunds(
      ledger,
      token,
      holder);
  }

  function recoverAllFunds(
    ERC20 token,
    address holder,
    bytes32[2] checksums,
    uint64 trail,
    bytes32[] allotmentChain,
    bytes32[] membershipChain,
    uint256[] values,
    uint256[2] LR, // solhint-disable-line func-param-name-mixedcase
    uint256[3] dummyPassiveMark
  )
    public
    onlyWhenContractPunished()
    returns (uint256 recovered)
  {
    recovered = RecoveryLib.recoverAllFunds(
      ledger,
      token,
      holder,
      checksums,
      trail,
      allotmentChain,
      membershipChain,
      values,
      LR,
      dummyPassiveMark);
  }
}
