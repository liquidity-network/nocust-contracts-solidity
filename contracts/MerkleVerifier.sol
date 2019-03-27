pragma solidity ^0.4.24;

import "./ERC20.sol";
import "./SafeMath/SafeMathLib32.sol";
import "./SafeMath/SafeMathLib64.sol";
import "./SafeMath/SafeMathLib256.sol";

/*
This library defines a collection of different checksumming procedures for
membership, exclusive allotment and data.
*/
library MerkleVerifier {
  using SafeMathLib32 for uint32;
  using SafeMathLib64 for uint64;
  using SafeMathLib256 for uint256;

  /**
   * Calculate a vanilla merkle root from a chain of hashes with a fixed height
   * starting from the leaf node.
   */
  function calculateMerkleRoot(
    uint256 trail,
    bytes32[] chain,
    bytes32 node
  )
    public
    pure
    returns (bytes32)
  {
    for (uint32 i = 0; i < chain.length; i++) {
      bool linkLeft = false;
      if (trail > 0) {
        linkLeft = trail.mod(2) == 1;
        trail = trail.div(2);
      }
      node = keccak256(abi.encodePacked(
        i,
        linkLeft ? chain[i] : node,
        linkLeft ? node : chain[i]
      ));
    }
    return node;
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
    return calculateMerkleRoot(trail, chain, node) == merkleRoot;
  }

  /**
   * Calculate an annotated merkle tree root from a chain of hashes and sibling
   * values with a fixed height starting from the leaf node.
   * @return the allotment of the root node.
   */
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
    require(
      value.length == allotmentChain.length,
      'p');

    require(
      LR[1] >= LR[0],
      's');
    for (uint32 i = 0; i < value.length; i++) {
      bool linkLeft = false; // is the current chain link on the left of this node
      if (allotmentTrail > 0) {
        linkLeft = allotmentTrail.mod(2) == 1;
        allotmentTrail = allotmentTrail.div(2);
      }

      node = keccak256(abi.encodePacked(
        i,
        linkLeft ? value[i] : LR[0], // leftmost value
        keccak256(abi.encodePacked(
          linkLeft ? allotmentChain[i] : node, // left node
          linkLeft ? LR[0] : LR[1], // middle value
          linkLeft ? node : allotmentChain[i] // right node
        )),
        linkLeft ? LR[1] : value[i] // rightmost value
      ));

      require(
        linkLeft ? value[i] <= LR[0] : LR[1] <= value[i],
        'x');

      LR[0] = linkLeft ? value[i] : LR[0];
      LR[1] = linkLeft ? LR[1] : value[i];

      require(
        LR[1] >= LR[0],
        't');
    }
    require(
      LR[0] == 0,
      'l');

    node = keccak256(abi.encodePacked(
      LR[0], node, LR[1]
    ));

    require(
      verifyProofOfMembership(membershipTrail, membershipChain, node, root),
      'm');

    return LR[1];
  }

  /**
   * Calculate an annotated merkle tree root from a combined array containing
   * the chain of hashes and sibling values with a fixed height starting from the
   * leaf node.
   */
  function verifyProofOfPassiveDelivery(
    uint64 allotmentTrail,
    bytes32 node,
    bytes32 root,
    bytes32[] chainValues,
    uint256[2] LR
  )
    public
    pure
    returns (uint256)
  {
    require(
      chainValues.length.mod(2) == 0,
      'p');

    require(
      LR[1] >= LR[0],
      's');
    uint32 v = uint32(chainValues.length.div(2));
    for (uint32 i = 0; i < v; i++) {
      bool linkLeft = false; // is the current chain link on the left of this node
      if (allotmentTrail > 0) {
        linkLeft = allotmentTrail.mod(2) == 1;
        allotmentTrail = allotmentTrail.div(2);
      }

      node = keccak256(abi.encodePacked(
        i,
        linkLeft ? uint256(chainValues[i.add(v)]) : LR[0], // leftmost value
        keccak256(abi.encodePacked(
          linkLeft ? chainValues[i] : node, // left node
          linkLeft ? LR[0] : LR[1], // middle value
          linkLeft ? node : chainValues[i] // right node
        )),
        linkLeft ? LR[1] : uint256(chainValues[i.add(v)]) // rightmost value
      ));

      require(
        linkLeft ? uint256(chainValues[i.add(v)]) <= LR[0] : LR[1] <= uint256(chainValues[i.add(v)]),
        'x');

      LR[0] = linkLeft ? uint256(chainValues[i.add(v)]) : LR[0];
      LR[1] = linkLeft ? LR[1] : uint256(chainValues[i.add(v)]);

      require(
        LR[1] >= LR[0],
        't');
    }
    require(
      LR[0] == 0,
      'l');

    require(
      node == root,
      'n');

    return LR[1];
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
    return keccak256(abi.encodePacked(
      keccak256(abi.encodePacked(counterparty)),
      amount,
      recipientTrail,
      nonce));
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
    return keccak256(abi.encodePacked(
      keccak256(abi.encodePacked(tokens[0])),
      keccak256(abi.encodePacked(tokens[1])),
      recipientTrail,
      sellAmount,
      buyAmount,
      startBalance,
      nonce));
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
    return keccak256(abi.encodePacked(
      keccak256(abi.encodePacked(address(this))),
      keccak256(abi.encodePacked(token)),
      keccak256(abi.encodePacked(holder)),
      trail,
      eon,
      txSetRoot,
      deltas[0],
      deltas[1]
    ));
  }
}
