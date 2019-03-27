pragma solidity ^0.4.24;

import "./BimodalProxy.sol";
import "./ERC20.sol";
import "./BimodalLib.sol";
import "./MerkleVerifier.sol";
import "./ChallengeLib.sol";
import "./SafeMath/SafeMathLib256.sol";

contract ChallengeProxy is BimodalProxy {
  using SafeMathLib256 for uint256;
  
  modifier onlyWithFairReimbursement() {
    uint256 gas = gasleft();
    _;
    gas = gas.sub(gasleft());
    require(
      msg.value >= gas.mul(ledger.MIN_CHALLENGE_GAS_COST) &&
      msg.value >= gas.mul(tx.gasprice),
      'r');
    ledger.operator.transfer(msg.value);
  }

  modifier onlyWithSkewedReimbursement(uint256 extra) {
    uint256 gas = gasleft();
    _;
    gas = gas.sub(gasleft());
    require(
      msg.value >= gas.add(extra).mul(ledger.MIN_CHALLENGE_GAS_COST) &&
      msg.value >= gas.add(extra).mul(tx.gasprice),
      'r');
    ledger.operator.transfer(msg.value);
  }

  // =========================================================================
  function verifyProofOfExclusiveAccountBalanceAllotment(
    ERC20 token,
    address holder,
    bytes32[2] activeStateChecksum_passiveTransfersRoot, // solhint-disable func-param-name-mixedcase
    uint64 trail,
    uint256[3] eonPassiveMark,
    bytes32[] allotmentChain,
    bytes32[] membershipChain,
    uint256[] values,
    uint256[2] LR // solhint-disable-line func-param-name-mixedcase
  )
    public
    view
    returns (bool)
  {
    return ChallengeLib.verifyProofOfExclusiveAccountBalanceAllotment(
      ledger,
      token,
      holder,
      activeStateChecksum_passiveTransfersRoot,
      trail,
      eonPassiveMark,
      allotmentChain,
      membershipChain,
      values,
      LR
    );
  }

  function verifyProofOfActiveStateUpdateAgreement(
    ERC20 token,
    address holder,
    uint64 trail,
    uint256 eon,
    bytes32 txSetRoot,
    uint256[2] deltas,
    address attester, bytes32 r, bytes32 s, uint8 v
  )
    public
    view
    returns (bytes32 checksum)
  {
    return ChallengeLib.verifyProofOfActiveStateUpdateAgreement(
      token,
      holder,
      trail,
      eon,
      txSetRoot,
      deltas,
      attester,
      r,
      s,
      v
    );
  }

  function verifyWithdrawalAuthorization(
    ERC20 token,
    address holder,
    uint256 expiry,
    uint256 amount,
    address attester,
    bytes32 r, bytes32 s, uint8 v
  )
    public
    view
    returns (bool)
  {
    return ChallengeLib.verifyWithdrawalAuthorization(
      token,
      holder,
      expiry,
      amount,
      attester,
      r,
      s,
      v
    );
  }

  function verifyProofOfExclusiveBalanceAllotment(
    uint64 allotmentTrail,
    uint64 membershipTrail,
    bytes32 node,
    bytes32 root,
    bytes32[] allotmentChain,
    bytes32[] membershipChain,
    uint256[] value,
    uint256[2] LR // solhint-disable-line func-param-name-mixedcase
  )
    public
    pure
    returns (uint256)
  {
    return MerkleVerifier.verifyProofOfExclusiveBalanceAllotment(
      allotmentTrail,
      membershipTrail,
      node,
      root,
      allotmentChain,
      membershipChain,
      value,
      LR
    );
  }

  function verifyProofOfMembership(
    uint256 trail,
    bytes32[] chain,
    bytes32 node,
    bytes32 merkleRoot
  )
    public
    pure
    returns (bool)
  {
    return MerkleVerifier.verifyProofOfMembership(
      trail,
      chain,
      node,
      merkleRoot
    );
  }

  function verifyProofOfPassiveDelivery(
    uint64 allotmentTrail,
    bytes32 node,
    bytes32 root,
    bytes32[] chainValues,
    uint256[2] LR // solhint-disable-line func-param-name-mixedcase
  )
    public
    pure
    returns (uint256)
  {
    return MerkleVerifier.verifyProofOfPassiveDelivery(
      allotmentTrail,
      node,
      root,
      chainValues,
      LR
    );
  }

  // =========================================================================
  function challengeStateUpdateWithProofOfExclusiveBalanceAllotment(
    ERC20 token,
    bytes32[2] checksums,
    uint64 trail,
    bytes32[] allotmentChain,
    bytes32[] membershipChain,
    uint256[] value,
    uint256[2][3] lrDeltasPassiveMark,
    bytes32[3] rsTxSetRoot,
    uint8 v
  )
    public
    payable
    onlyWithFairReimbursement()
  {
    ChallengeLib.challengeStateUpdateWithProofOfExclusiveBalanceAllotment(
      ledger,
      token,
      checksums,
      trail,
      allotmentChain,
      membershipChain,
      value,
      lrDeltasPassiveMark,
      rsTxSetRoot,
      v
    );
  }
  
  function challengeStateUpdateWithProofOfActiveStateUpdateAgreement(
    ERC20 token,
    bytes32 txSetRoot,
    uint64 trail,
    uint256[2] deltas,
    bytes32 r, bytes32 s, uint8 v
  )
    public
    payable
    onlyWithSkewedReimbursement(25) /* TODO calculate exact addition */
  {
    ChallengeLib.challengeStateUpdateWithProofOfActiveStateUpdateAgreement(
      ledger,
      token,
      txSetRoot,
      trail,
      deltas,
      r,
      s,
      v
    );
  }

  function answerStateUpdateChallenge(
    ERC20 token,
    address issuer,
    bytes32[] allotmentChain,
    bytes32[] membershipChain,
    uint256[] values,
    uint256[2][3] lrDeltasPassiveMark, // [ [L, R], Deltas ]
    bytes32[6] rSrStxSetRootChecksum,
    uint8[2] v
  )
    public
  {
    ChallengeLib.answerStateUpdateChallenge(
      ledger,
      token,
      issuer,
      allotmentChain,
      membershipChain,
      values,
      lrDeltasPassiveMark,
      rSrStxSetRootChecksum,
      v
    );
  }

  // =========================================================================
  function challengeTransferDeliveryWithProofOfActiveStateUpdateAgreement(
    ERC20 token,
    address[2] SR, // solhint-disable-line func-param-name-mixedcase
    uint256[2] nonceAmount,
    uint64[3] trails,
    bytes32[] chain,
    uint256[2] deltas,
    bytes32[3] rsTxSetRoot,
    uint8 v
  )
    public
    payable
    onlyWithFairReimbursement()
  {
    ChallengeLib.challengeTransferDeliveryWithProofOfActiveStateUpdateAgreement(
      ledger,
      token,
      SR,
      nonceAmount,
      trails,
      chain,
      deltas,
      rsTxSetRoot,
      v
    );
  }

  function answerTransferDeliveryChallengeWithProofOfActiveStateUpdateAgreement(
    ERC20 token,
    address[2] SR, // solhint-disable-line func-param-name-mixedcase
    uint64 transferMembershipTrail,
    bytes32[] allotmentChain,
    bytes32[] membershipChain,
    uint256[] values,
    uint256[2][3] lrDeltasPassiveMark,
    bytes32[2] txSetRootChecksum,
    bytes32[] txChain
  )
    public
  {
    ChallengeLib.answerTransferDeliveryChallengeWithProofOfActiveStateUpdateAgreement(
      ledger,
      token,
      SR,
      transferMembershipTrail,
      allotmentChain,
      membershipChain,
      values,
      lrDeltasPassiveMark,
      txSetRootChecksum,
      txChain
    );
  }

  // =========================================================================
  function challengeTransferDeliveryWithProofOfPassiveStateUpdate(
    ERC20 token,
    address[2] SR, // solhint-disable-line func-param-name-mixedcase
    bytes32[2] txSetRootChecksum,
    uint64[3] senderTransferRecipientTrails,
    bytes32[] allotmentChain,
    bytes32[] membershipChain,
    uint256[] values,
    uint256[2][4] lrDeltasPassiveMarkDummyAmount,
    bytes32[] transferMembershipChain
  )
    public
    payable
    onlyWithFairReimbursement()
  {
    ChallengeLib.challengeTransferDeliveryWithProofOfPassiveStateUpdate(
      ledger,
      token,
      SR,
      txSetRootChecksum,
      senderTransferRecipientTrails,
      allotmentChain,
      membershipChain,
      values,
      lrDeltasPassiveMarkDummyAmount,
      transferMembershipChain
    );
  }

  function answerTransferDeliveryChallengeWithProofOfPassiveStateUpdate(
    ERC20 token,
    address[2] SR, // solhint-disable-line func-param-name-mixedcase
    uint64 transferMembershipTrail,
    bytes32[] allotmentChain,
    bytes32[] membershipChain,
    uint256[] values,
    uint256[2][3] lrPassiveMarkPositionNonce,
    bytes32[2] checksums,
    bytes32[] txChainValues
  )
    public
  {
    ChallengeLib.answerTransferDeliveryChallengeWithProofOfPassiveStateUpdate(
      ledger,
      token,
      SR,
      transferMembershipTrail,
      allotmentChain,
      membershipChain,
      values,
      lrPassiveMarkPositionNonce,
      checksums,
      txChainValues
    );
  }

  // =========================================================================
  function challengeSwapEnactmentWithProofOfActiveStateUpdateAgreement(
    ERC20[2] tokens,
    uint64[3] senderTransferRecipientTrails,
    bytes32[] allotmentChain,
    bytes32[] membershipChain,
    bytes32[] txChain,
    uint256[] values,
    uint256[2][3] lrDeltasPassiveMark,
    uint256[4] sellBuyBalanceNonce,
    bytes32[3] txSetRootChecksumDummy
  )
    public
    payable
    onlyWithFairReimbursement()
  {
    ChallengeLib.challengeSwapEnactmentWithProofOfActiveStateUpdateAgreement(
      ledger,
      tokens,
      senderTransferRecipientTrails,
      allotmentChain,
      membershipChain,
      txChain,
      values,
      lrDeltasPassiveMark,
      sellBuyBalanceNonce,
      txSetRootChecksumDummy
    );
  }

  function answerSwapChallengeWithProofOfExclusiveBalanceAllotment(
    ERC20[2] tokens,
    address issuer,
    uint64 transferMembershipTrail,
    bytes32[] allotmentChain,
    bytes32[] membershipChain,
    bytes32[] txChain,
    uint256[] values,
    uint256[2][3] lrDeltasPassiveMark,
    uint256 balance,
    bytes32[3] txSetRootChecksumDummy
  )
    public
  {
    ChallengeLib.answerSwapChallengeWithProofOfExclusiveBalanceAllotment(
      ledger,
      tokens,
      issuer,
      transferMembershipTrail,
      allotmentChain,
      membershipChain,
      txChain,
      values,
      lrDeltasPassiveMark,
      balance,
      txSetRootChecksumDummy
    );
  }

  // =========================================================================
  function slashWithdrawalWithProofOfMinimumAvailableBalance(
    ERC20 token,
    address withdrawer,
    uint256[2] markerEonAvailable,
    bytes32[2] rs,
    uint8 v
  )
    public
    returns (uint256[2])
  {
    return ChallengeLib.slashWithdrawalWithProofOfMinimumAvailableBalance(
      ledger,
      token,
      withdrawer,
      markerEonAvailable,
      rs,
      v
    );
  }
}
