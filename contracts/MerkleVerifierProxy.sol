pragma solidity ^0.4.24;

import "./ERC20.sol";
import "./MerkleVerifier.sol";

contract MerkleVerifierProxy {
  function calculateMerkleRoot(
    uint256 trail,
    bytes32[] chain,
    bytes32 node
  )
    public
    pure
    returns (bytes32)
  {
    return MerkleVerifier.calculateMerkleRoot(trail, chain, node);
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
    MerkleVerifier.verifyProofOfPassiveDelivery(
      allotmentTrail,
      node,
      root,
      chainValues,
      LR
    );
  }

  function transferChecksum(
    address counterparty,
    uint256 amount,
    uint64 recipientTrail,
    uint256 nonce
  )
    public
    pure
    returns (bytes32)
  {
    return MerkleVerifier.transferChecksum(
      counterparty,
      amount,
      recipientTrail,
      nonce
    );
  }

  function swapOrderChecksum(
    ERC20[2] tokens,
    uint64 recipientTrail,
    uint256 sellAmount,
    uint256 buyAmount,
    uint256 startBalance,
    uint256 nonce
  )
    public
    pure
    returns (bytes32)
  {
    return MerkleVerifier.swapOrderChecksum(
      tokens,
      recipientTrail,
      sellAmount,
      buyAmount,
      startBalance,
      nonce
    );
  }

  function activeStateUpdateChecksum(
    ERC20 token,
    address holder,
    uint64 trail,
    uint256 eon,
    bytes32 txSetRoot,
    uint256[2] deltas
  )
    public
    view
    returns (bytes32)
  {
    return MerkleVerifier.activeStateUpdateChecksum(
      token,
      holder,
      trail,
      eon,
      txSetRoot,
      deltas
    );
  }
}
