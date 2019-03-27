/* solhint-disable func-order */

pragma solidity ^0.4.24;

import "./BimodalLib.sol";
import "./MerkleVerifier.sol";
import "./SafeMath/SafeMathLib32.sol";
import "./SafeMath/SafeMathLib256.sol";

/**
 * This library contains the challenge-response implementations of NOCUST.
 */
library ChallengeLib {
  using SafeMathLib256 for uint256;
  using SafeMathLib32 for uint32;
  using BimodalLib for BimodalLib.Ledger;
  // EVENTS
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
    bytes32 r, bytes32 s, uint8 v
  );

  // Validation
  function verifyProofOfExclusiveAccountBalanceAllotment(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    address holder,
    bytes32[2] activeStateChecksum_passiveTransfersRoot,  // solhint-disable func-param-name-mixedcase
    uint64 trail,
    uint256[3] eonPassiveMark,
    bytes32[] allotmentChain,
    bytes32[] membershipChain,
    uint256[] values,
    uint256[2] LR  // solhint-disable func-param-name-mixedcase
  )
    public
    view
    returns (bool)
  {
    BimodalLib.Checkpoint memory checkpoint = ledger.checkpoints[eonPassiveMark[0].mod(ledger.EONS_KEPT)];
    require(eonPassiveMark[0] == checkpoint.eonNumber, 'r');

    // activeStateChecksum is set to the account node.
    activeStateChecksum_passiveTransfersRoot[0] = keccak256(abi.encodePacked(
      keccak256(abi.encodePacked(address(this))),
      keccak256(abi.encodePacked(token)),
      keccak256(abi.encodePacked(holder)),
      keccak256(abi.encodePacked(
        activeStateChecksum_passiveTransfersRoot[1], // passiveTransfersRoot
        eonPassiveMark[1],
        eonPassiveMark[2])),
      activeStateChecksum_passiveTransfersRoot[0] // activeStateChecksum
    ));
    // the interval allotment is set to form the leaf
    activeStateChecksum_passiveTransfersRoot[0] = keccak256(abi.encodePacked(
      LR[0], activeStateChecksum_passiveTransfersRoot[0], LR[1]
    ));

    // This calls the merkle verification procedure, which returns the
    // checkpoint allotment size
    uint64 tokenTrail = ledger.tokenToTrail[token];
    LR[0] = MerkleVerifier.verifyProofOfExclusiveBalanceAllotment(
      trail,
      tokenTrail,
      activeStateChecksum_passiveTransfersRoot[0],
      checkpoint.merkleRoot,
      allotmentChain,
      membershipChain,
      values,
      LR);

    // The previous allotment size of the target eon is reconstructed from the
    // deposits and withdrawals performed so far and the current balance.
    LR[1] = address(this).balance;

    if (token != address(this)) {
      require(
        tokenTrail != 0,
        't');
      LR[1] = token.balanceOf(this);
    }

    // Credit back confirmed withdrawals that were performed since target eon
    for (tokenTrail = 0; tokenTrail < ledger.EONS_KEPT; tokenTrail++) {
      if (ledger.confirmedWithdrawals[token][tokenTrail].eon >= eonPassiveMark[0]) {
        LR[1] = LR[1].add(ledger.confirmedWithdrawals[token][tokenTrail].amount);
      }
    }
    // Debit deposits performed since target eon
    for (tokenTrail = 0; tokenTrail < ledger.EONS_KEPT; tokenTrail++) {
      if (ledger.deposits[token][tokenTrail].eon >= eonPassiveMark[0]) {
        LR[1] = LR[1].sub(ledger.deposits[token][tokenTrail].amount);
      }
    }
    // Debit withdrawals pending since prior eon
    LR[1] = LR[1].sub(ledger.getPendingWithdrawalsAtEon(token, eonPassiveMark[0].sub(1)));
    // Require that the reconstructed allotment matches the proof allotment
    require(
      LR[0] <= LR[1],
      'b');

    return true;
  }

  function verifyProofOfActiveStateUpdateAgreement(
    ERC20 token,
    address holder,
    uint64 trail,
    uint256 eon,
    bytes32 txSetRoot,
    uint256[2] deltas,
    address attester,
    bytes32 r,
    bytes32 s,
    uint8 v
  )
    public
    view
    returns (bytes32 checksum)
  {
    checksum = MerkleVerifier.activeStateUpdateChecksum(token, holder, trail, eon, txSetRoot, deltas);
    require(attester == BimodalLib.signedMessageECRECOVER(checksum, r, s, v), 'A');
  }

  function verifyWithdrawalAuthorization(
    ERC20 token,
    address holder,
    uint256 expiry,
    uint256 amount,
    address attester,
    bytes32 r,
    bytes32 s,
    uint8 v
  )
    public
    view
    returns (bool)
  {
    bytes32 checksum = keccak256(abi.encodePacked(
      keccak256(abi.encodePacked(address(this))),
      keccak256(abi.encodePacked(token)),
      keccak256(abi.encodePacked(holder)),
      expiry,
      amount));
    require(attester == BimodalLib.signedMessageECRECOVER(checksum, r, s, v), 'a');
    return true;
  }

  // Challenge Lifecycle Methods
  /**
   * This method increments the live challenge counter and emits and event
   * containing the challenge index.
   */
  function markChallengeLive(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    address recipient,
    address sender
  )
    private
  {
    require(ledger.currentEra() > ledger.BLOCKS_PER_EPOCH);

    uint256 eon = ledger.currentEon();
    BimodalLib.Checkpoint storage checkpoint = ledger.getOrCreateCheckpoint(eon, eon);
    checkpoint.liveChallenges = checkpoint.liveChallenges.add(1);
    emit ChallengeIssued(token, recipient, sender);
  }

  /**
   * This method clears all the data in a Challenge structure and decrements the
   * live challenge counter.
   */
  function clearChallenge(
    BimodalLib.Ledger storage ledger,
    BimodalLib.Challenge storage challenge
  )
    private
  {
    BimodalLib.Checkpoint storage checkpoint = ledger.getOrCreateCheckpoint(
      challenge.initialStateEon.add(1),
      ledger.currentEon());
    checkpoint.liveChallenges = checkpoint.liveChallenges.sub(1);

    challenge.challengeType = BimodalLib.ChallengeType.NONE;
    challenge.block = 0;
    // challenge.initialStateEon = 0;
    challenge.initialStateBalance = 0;
    challenge.deltaHighestSpendings = 0;
    challenge.deltaHighestGains = 0;
    challenge.finalStateBalance = 0;
    challenge.deliveredTxNonce = 0;
    challenge.trailIdentifier = 0;
  }

  /**
   * This method marks a challenge as having been successfully answered only if
   * the response was provided in time.
   */
  function markChallengeAnswered(
    BimodalLib.Ledger storage ledger,
    BimodalLib.Challenge storage challenge
  )
    private
  {
    uint256 eon = ledger.currentEon();

    require(
      challenge.challengeType != BimodalLib.ChallengeType.NONE &&
      block.number.sub(challenge.block) < ledger.BLOCKS_PER_EPOCH &&
      (
        challenge.initialStateEon == eon.sub(1) ||
        (challenge.initialStateEon == eon.sub(2) && ledger.currentEra() < ledger.BLOCKS_PER_EPOCH)
      )
    );

    clearChallenge(ledger, challenge);
  }

  // ========================================================================
  // ========================================================================
  // ========================================================================
  // ====================================  STATE UPDATE Challenge
  // ========================================================================
  // ========================================================================
  // ========================================================================
  /**
   * This method initiates the fields of the Challenge struct to hold a state
   * update challenge.
   */
  function initStateUpdateChallenge(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    uint256 owed,
    uint256[2] spentGained,
    uint64 trail
  )
    private
  {
    BimodalLib.Challenge storage challengeEntry = ledger.challengeBook[token][msg.sender][msg.sender];
    require(challengeEntry.challengeType == BimodalLib.ChallengeType.NONE);
    require(challengeEntry.initialStateEon < ledger.currentEon().sub(1));

    challengeEntry.initialStateEon = ledger.currentEon().sub(1);
    challengeEntry.initialStateBalance = owed;
    challengeEntry.deltaHighestSpendings = spentGained[0];
    challengeEntry.deltaHighestGains = spentGained[1];
    challengeEntry.trailIdentifier = trail;

    challengeEntry.challengeType = BimodalLib.ChallengeType.STATE_UPDATE;
    challengeEntry.block = block.number;

    markChallengeLive(ledger, token, msg.sender, msg.sender);
  }

  /**
   * This method checks that the updated balance is at least as much as the
   * expected balance.
   */
  function checkStateUpdateBalance(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    BimodalLib.Challenge storage challenge,
    uint256[2] LR, // solhint-disable func-param-name-mixedcase
    uint256[2] spentGained,
    uint256 passivelyReceived
  )
    private
    view
  {
    (uint256 deposits, uint256 withdrawals) = ledger.getCurrentEonDepositsWithdrawals(token, msg.sender);
    uint256 incoming = spentGained[1] // actively received in commit chain
                      .add(deposits)
                      .add(passivelyReceived);
    uint256 outgoing = spentGained[0] // actively spent in commit chain
                      .add(withdrawals);
    // This verification is modified to permit underflow of expected balance
    // since a client can choose to zero the `challenge.initialStateBalance`
    require(
      challenge.initialStateBalance
      .add(incoming)
      <=
      LR[1].sub(LR[0]) // final balance allotment
      .add(outgoing)
      ,
      'B');
  }

  function challengeStateUpdateWithProofOfExclusiveBalanceAllotment(
    BimodalLib.Ledger storage ledger,
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
    /* payable */
    /* onlyWithFairReimbursement(ledger) */
  {
    uint256 previousEon = ledger.currentEon().sub(1);
    address operator = ledger.operator;

    // The hub must have committed to this state update
    if (lrDeltasPassiveMark[1][0] != 0 || lrDeltasPassiveMark[1][1] != 0) {
      verifyProofOfActiveStateUpdateAgreement(
        token,
        msg.sender,
        trail,
        previousEon,
        rsTxSetRoot[2],
        lrDeltasPassiveMark[1],
        operator,
        rsTxSetRoot[0], rsTxSetRoot[1], v);
    }

    initStateUpdateChallenge(
      ledger,
      token,
      lrDeltasPassiveMark[0][1].sub(lrDeltasPassiveMark[0][0]),
      lrDeltasPassiveMark[1],
      trail);

    // The initial state must have been ratified in the commitment
    require(verifyProofOfExclusiveAccountBalanceAllotment(
      ledger,
      token,
      msg.sender,
      checksums,
      trail,
      [previousEon, lrDeltasPassiveMark[2][0], lrDeltasPassiveMark[2][1]],
      allotmentChain,
      membershipChain,
      value,
      lrDeltasPassiveMark[0]));
  }

  function challengeStateUpdateWithProofOfActiveStateUpdateAgreement(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    bytes32 txSetRoot,
    uint64 trail,
    uint256[2] deltas,
    bytes32 r,
    bytes32 s,
    uint8 v
  )
    public
    /* payable */
    /* TODO calculate exact addition */
    /* onlyWithSkewedReimbursement(ledger, 25) */
  {
    // The hub must have committed to this transition
    verifyProofOfActiveStateUpdateAgreement(
      token,
      msg.sender,
      trail,
      ledger.currentEon().sub(1),
      txSetRoot,
      deltas,
      ledger.operator,
      r, s, v);

    initStateUpdateChallenge(ledger, token, 0, deltas, trail);
  }

  function answerStateUpdateChallenge(
    BimodalLib.Ledger storage ledger,
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
    BimodalLib.Challenge storage challenge = ledger.challengeBook[token][issuer][issuer];
    require(challenge.challengeType == BimodalLib.ChallengeType.STATE_UPDATE);

    // Transition must have been approved by issuer
    if (lrDeltasPassiveMark[1][0] != 0 || lrDeltasPassiveMark[1][1] != 0) {
      rSrStxSetRootChecksum[0] = verifyProofOfActiveStateUpdateAgreement(
        token,
        issuer,
        challenge.trailIdentifier,
        challenge.initialStateEon,
        rSrStxSetRootChecksum[4], // txSetRoot
        lrDeltasPassiveMark[1], // deltas
        issuer,
        rSrStxSetRootChecksum[0], // R[0]
        rSrStxSetRootChecksum[1], // S[0]
        v[0]);
      address operator = ledger.operator;
      rSrStxSetRootChecksum[1] = verifyProofOfActiveStateUpdateAgreement(
        token,
        issuer,
        challenge.trailIdentifier,
        challenge.initialStateEon,
        rSrStxSetRootChecksum[4], // txSetRoot
        lrDeltasPassiveMark[1], // deltas
        operator,
        rSrStxSetRootChecksum[2], // R[1]
        rSrStxSetRootChecksum[3], // S[1]
        v[1]);
      require(rSrStxSetRootChecksum[0] == rSrStxSetRootChecksum[1], 'u');
    } else {
      rSrStxSetRootChecksum[0] = bytes32(0);
    }

    // Transition has to be at least as recent as submitted one
    require(
      lrDeltasPassiveMark[1][0] >= challenge.deltaHighestSpendings &&
      lrDeltasPassiveMark[1][1] >= challenge.deltaHighestGains,
      'x');

    // Transition has to have been properly applied
    checkStateUpdateBalance(
      ledger,
      token,
      challenge,
      lrDeltasPassiveMark[0], // LR
      lrDeltasPassiveMark[1], // deltas
      lrDeltasPassiveMark[2][0]); // passive amount

    // Truffle crashes when trying to interpret this event in some cases.
    emit StateUpdate(
      token,
      issuer,
      challenge.initialStateEon.add(1),
      challenge.trailIdentifier,
      allotmentChain,
      membershipChain,
      values,
      lrDeltasPassiveMark,
      rSrStxSetRootChecksum[0], // activeStateChecksum
      rSrStxSetRootChecksum[5], // passiveAcceptChecksum
      rSrStxSetRootChecksum[2], // R[1]
      rSrStxSetRootChecksum[3], // S[1]
      v[1]);

    // Proof of stake must be ratified in the checkpoint
    require(verifyProofOfExclusiveAccountBalanceAllotment(
        ledger,
        token,
        issuer,
        [rSrStxSetRootChecksum[0], rSrStxSetRootChecksum[5]], // activeStateChecksum, passiveAcceptChecksum
        challenge.trailIdentifier,
        [
          challenge.initialStateEon.add(1), // eonNumber
          lrDeltasPassiveMark[2][0], // passiveAmount
          lrDeltasPassiveMark[2][1]
        ],
        allotmentChain,
        membershipChain,
        values,
        lrDeltasPassiveMark[0]), // LR
      'c');

    markChallengeAnswered(ledger, challenge);
  }

  // ========================================================================
  // ========================================================================
  // ========================================================================
  // ====================================  ACTIVE DELIVERY Challenge
  // ========================================================================
  // ========================================================================
  // ========================================================================
  function initTransferDeliveryChallenge(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    address sender,
    address recipient,
    uint256 amount,
    uint256 txNonce,
    uint64 trail
  )
    private
  {
    BimodalLib.Challenge storage challenge = ledger.challengeBook[token][recipient][sender];
    require(challenge.challengeType == BimodalLib.ChallengeType.NONE);
    require(challenge.initialStateEon < ledger.currentEon().sub(1));

    challenge.challengeType = BimodalLib.ChallengeType.TRANSFER_DELIVERY;
    challenge.initialStateEon = ledger.currentEon().sub(1);
    challenge.deliveredTxNonce = txNonce;
    challenge.block = block.number;
    challenge.trailIdentifier = trail;
    challenge.finalStateBalance = amount;

    markChallengeLive(
      ledger,
      token,
      recipient,
      sender);
  }

  function challengeTransferDeliveryWithProofOfActiveStateUpdateAgreement(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    address[2] SR,  // solhint-disable func-param-name-mixedcase
    uint256[2] nonceAmount,
    uint64[3] trails,
    bytes32[] chain,
    uint256[2] deltas,
    bytes32[3] rsTxSetRoot,
    uint8 v
  )
    public
    /* payable */
    /* onlyWithFairReimbursement() */
  {
    require(msg.sender == SR[0] || msg.sender == SR[1], 'd');

    // Require hub to have committed to transition
    verifyProofOfActiveStateUpdateAgreement(
      token,
      SR[0],
      trails[0],
      ledger.currentEon().sub(1),
      rsTxSetRoot[2],
      deltas,
      ledger.operator,
      rsTxSetRoot[0], rsTxSetRoot[1], v);

    rsTxSetRoot[0] = MerkleVerifier.transferChecksum(
      SR[1],
      nonceAmount[1], // amount
      trails[2],
      nonceAmount[0]); // nonce

    // Require tx to exist in transition
    require(MerkleVerifier.verifyProofOfMembership(
      trails[1],
      chain,
      rsTxSetRoot[0], // transferChecksum
      rsTxSetRoot[2]), // txSetRoot
      'e');

    initTransferDeliveryChallenge(
      ledger,
      token,
      SR[0], // senderAddress
      SR[1], // recipientAddress
      nonceAmount[1], // amount
      nonceAmount[0], // nonce
      trails[2]); // recipientTrail
  }

  function answerTransferDeliveryChallengeWithProofOfActiveStateUpdateAgreement(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    address[2] SR,  // solhint-disable func-param-name-mixedcase
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
    BimodalLib.Challenge storage challenge = ledger.challengeBook[token][SR[1]][SR[0]];
    require(challenge.challengeType == BimodalLib.ChallengeType.TRANSFER_DELIVERY);

    // Assert that the challenged transaction belongs to the transfer set
    require(MerkleVerifier.verifyProofOfMembership(
      transferMembershipTrail,
      txChain,
      MerkleVerifier.transferChecksum(
        SR[0],
        challenge.finalStateBalance, // amount
        challenge.trailIdentifier, // recipient trail
        challenge.deliveredTxNonce),
      txSetRootChecksum[0])); // txSetRoot

    // Require committed transition to include transfer
    txSetRootChecksum[0] = MerkleVerifier.activeStateUpdateChecksum(
      token,
      SR[1],
      challenge.trailIdentifier,
      challenge.initialStateEon,
      txSetRootChecksum[0], // txSetRoot
      lrDeltasPassiveMark[1]); // Deltas

    // Assert that this transition was used to update the recipient's stake
    require(verifyProofOfExclusiveAccountBalanceAllotment(
      ledger,
      token,
      SR[1], // recipient
      txSetRootChecksum, // [activeStateChecksum, passiveChecksum]
      challenge.trailIdentifier,
      [
        challenge.initialStateEon.add(1), // eonNumber
        lrDeltasPassiveMark[2][0], // passiveAmount
        lrDeltasPassiveMark[2][1] // passiveMark
      ],
      allotmentChain,
      membershipChain,
      values,
      lrDeltasPassiveMark[0])); // LR

    markChallengeAnswered(ledger, challenge);
  }

  // ========================================================================
  // ========================================================================
  // ========================================================================
  // ====================================  PASSIVE DELIVERY Challenge
  // ========================================================================
  // ========================================================================
  // ========================================================================
  function challengeTransferDeliveryWithProofOfPassiveStateUpdate(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    address[2] SR,  // solhint-disable func-param-name-mixedcase
    bytes32[2] txSetRootChecksum,
    uint64[3] senderTransferRecipientTrails,
    bytes32[] allotmentChain,
    bytes32[] membershipChain,
    uint256[] values,
    uint256[2][4] lrDeltasPassiveMarkDummyAmount,
    bytes32[] transferMembershipChain
  )
    public
    /* payable */
    /* onlyWithFairReimbursement() */
  {
    require(msg.sender == SR[0] || msg.sender == SR[1], 'd');
    lrDeltasPassiveMarkDummyAmount[3][0] = ledger.currentEon().sub(1); // previousEon

    // Assert that the challenged transaction ends the transfer set
    require(MerkleVerifier.verifyProofOfMembership(
      senderTransferRecipientTrails[1], // transferMembershipTrail
      transferMembershipChain,
      MerkleVerifier.transferChecksum(
        SR[1], // recipientAddress
        lrDeltasPassiveMarkDummyAmount[3][1], // amount
        senderTransferRecipientTrails[2], // recipientTrail
        2 ** 256 - 1), // nonce
      txSetRootChecksum[0]), // txSetRoot
      'e');

    // Require committed transition to include transfer
    txSetRootChecksum[0] = MerkleVerifier.activeStateUpdateChecksum(
      token,
      SR[0], // senderAddress
      senderTransferRecipientTrails[0], // senderTrail
      lrDeltasPassiveMarkDummyAmount[3][0], // previousEon
      txSetRootChecksum[0], // txSetRoot
      lrDeltasPassiveMarkDummyAmount[1]); // Deltas

    // Assert that this transition was used to update the sender's stake
    require(verifyProofOfExclusiveAccountBalanceAllotment(
      ledger,
      token,
      SR[0], // senderAddress
      txSetRootChecksum, // [activeStateChecksum, passiveChecksum]
      senderTransferRecipientTrails[0], // senderTrail
      [
        lrDeltasPassiveMarkDummyAmount[3][0].add(1), // eonNumber
        lrDeltasPassiveMarkDummyAmount[2][0], // passiveAmount
        lrDeltasPassiveMarkDummyAmount[2][1] // passiveMark
      ],
      allotmentChain,
      membershipChain,
      values,
      lrDeltasPassiveMarkDummyAmount[0])); // LR

    initTransferDeliveryChallenge(
      ledger,
      token,
      SR[0], // sender
      SR[1], // recipient
      lrDeltasPassiveMarkDummyAmount[3][1], // amount
      uint256(keccak256(abi.encodePacked(lrDeltasPassiveMarkDummyAmount[2][1], uint256(2 ** 256 - 1)))), // mark (nonce)
      senderTransferRecipientTrails[2]); // recipientTrail
  }

  function answerTransferDeliveryChallengeWithProofOfPassiveStateUpdate(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    address[2] SR,  // solhint-disable func-param-name-mixedcase
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
    BimodalLib.Challenge storage challenge = ledger.challengeBook[token][SR[1]][SR[0]];
    require(challenge.challengeType == BimodalLib.ChallengeType.TRANSFER_DELIVERY);
    require(
      challenge.deliveredTxNonce ==
      uint256(keccak256(abi.encodePacked(lrPassiveMarkPositionNonce[2][0], lrPassiveMarkPositionNonce[2][1])))
    );

    // Assert that the challenged transaction belongs to the passively delivered set
    require(
      MerkleVerifier.verifyProofOfPassiveDelivery(
        transferMembershipTrail,
        MerkleVerifier.transferChecksum( // node
          SR[0], // sender
          challenge.finalStateBalance, // amount
          challenge.trailIdentifier, // recipient trail
          challenge.deliveredTxNonce),
        checksums[1], // passiveChecksum
        txChainValues,
        [lrPassiveMarkPositionNonce[2][0], lrPassiveMarkPositionNonce[2][0].add(challenge.finalStateBalance)])
      <=
      lrPassiveMarkPositionNonce[1][0]);

    // Assert that this transition was used to update the recipient's stake
    require(verifyProofOfExclusiveAccountBalanceAllotment(
      ledger,
      token,
      SR[1], // recipient
      checksums, // [activeStateChecksum, passiveChecksum]
      challenge.trailIdentifier, // recipientTrail
      [
        challenge.initialStateEon.add(1), // eonNumber
        lrPassiveMarkPositionNonce[1][0], // passiveAmount
        lrPassiveMarkPositionNonce[1][1] // passiveMark
      ],
      allotmentChain,
      membershipChain,
      values,
      lrPassiveMarkPositionNonce[0])); // LR

    markChallengeAnswered(ledger, challenge);
  }

  // ========================================================================
  // ========================================================================
  // ========================================================================
  // ====================================  SWAP Challenge
  // ========================================================================
  // ========================================================================
  // ========================================================================
  function initSwapEnactmentChallenge(
    BimodalLib.Ledger storage ledger,
    ERC20[2] tokens,
    uint256[4] updatedSpentGainedPassive,
    uint256[4] sellBuyBalanceNonce,
    uint64 recipientTrail
  )
    private
  {
    ERC20 conduit = ERC20(address(keccak256(abi.encodePacked(tokens[0], tokens[1]))));
    BimodalLib.Challenge storage challenge = ledger.challengeBook[conduit][msg.sender][msg.sender];
    require(challenge.challengeType == BimodalLib.ChallengeType.NONE);
    require(challenge.initialStateEon < ledger.currentEon().sub(1));

    challenge.initialStateEon = ledger.currentEon().sub(1);
    challenge.deliveredTxNonce = sellBuyBalanceNonce[3];
    challenge.challengeType = BimodalLib.ChallengeType.SWAP_ENACTMENT;
    challenge.block = block.number;
    challenge.trailIdentifier = recipientTrail;
    challenge.deltaHighestSpendings = sellBuyBalanceNonce[0];
    challenge.deltaHighestGains = sellBuyBalanceNonce[1];

    (uint256 deposits, uint256 withdrawals) = ledger.getCurrentEonDepositsWithdrawals(tokens[0], msg.sender);

    challenge.initialStateBalance =
      sellBuyBalanceNonce[2] // allotment from eon e - 1
        .add(updatedSpentGainedPassive[2]) // gained
        .add(updatedSpentGainedPassive[3]) // passively delivered
        .add(deposits)
        .sub(updatedSpentGainedPassive[1]) // spent
        .sub(withdrawals);
    challenge.finalStateBalance = updatedSpentGainedPassive[0];

    require(challenge.finalStateBalance >= challenge.initialStateBalance, 'd');

    markChallengeLive(ledger, conduit, msg.sender, msg.sender);
  }

  function challengeSwapEnactmentWithProofOfActiveStateUpdateAgreement(
    BimodalLib.Ledger storage ledger,
    ERC20[2] tokens,
    uint64[3] senderTransferRecipientTrails, // senderTransferRecipientTrails
    bytes32[] allotmentChain,
    bytes32[] membershipChain,
    bytes32[] txChain,
    uint256[] values,
    uint256[2][3] lrDeltasPassiveMark,
    uint256[4] sellBuyBalanceNonce,
    bytes32[3] txSetRootChecksumDummy
  )
    public
    /* payable */
    /* onlyWithFairReimbursement() */
  {
    // Require swap to exist in transition
    txSetRootChecksumDummy[2] = MerkleVerifier.swapOrderChecksum(
      tokens,
      senderTransferRecipientTrails[2],
      sellBuyBalanceNonce[0], // sell
      sellBuyBalanceNonce[1], // buy
      sellBuyBalanceNonce[2], // balance
      sellBuyBalanceNonce[3]); // nonce

    require(MerkleVerifier.verifyProofOfMembership(
      senderTransferRecipientTrails[1],
      txChain,
      txSetRootChecksumDummy[2], // swapOrderChecksum
      txSetRootChecksumDummy[0]), // txSetRoot
      'e');

    uint256 previousEon = ledger.currentEon().sub(1);

    // Require committed transition to include swap
    txSetRootChecksumDummy[2] = MerkleVerifier.activeStateUpdateChecksum(
      tokens[0],
      msg.sender,
      senderTransferRecipientTrails[0],
      previousEon,
      txSetRootChecksumDummy[0],
      lrDeltasPassiveMark[1]); // deltas

    uint256 updatedBalance = lrDeltasPassiveMark[0][1].sub(lrDeltasPassiveMark[0][0]);
    // The state must have been ratified in the commitment
    require(verifyProofOfExclusiveAccountBalanceAllotment(
      ledger,
      tokens[0],
      msg.sender,
      [txSetRootChecksumDummy[2], txSetRootChecksumDummy[1]], // [activeStateChecksum, passiveChecksum]
      senderTransferRecipientTrails[0],
      [
        previousEon.add(1), // eonNumber
        lrDeltasPassiveMark[2][0], // passiveAmount
        lrDeltasPassiveMark[2][1] // passiveMark
      ],
      allotmentChain,
      membershipChain,
      values,
      lrDeltasPassiveMark[0])); // LR

    initSwapEnactmentChallenge(
      ledger,
      tokens,
      [
        updatedBalance, // updated
        lrDeltasPassiveMark[1][0], // spent
        lrDeltasPassiveMark[1][1], // gained
        lrDeltasPassiveMark[2][0]], // passiveAmount
      sellBuyBalanceNonce,
      senderTransferRecipientTrails[2]);
  }

  /**
   * This method just calculates the total expected balance.
   */
  function calculateSwapConsistencyBalance(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    uint256[2] deltas,
    uint256 passiveAmount,
    uint256 balance
  )
    private
    view
    returns (uint256)
  {
    (uint256 deposits, uint256 withdrawals) = ledger.getCurrentEonDepositsWithdrawals(token, msg.sender);

    return balance
      .add(deltas[1]) // gained
      .add(passiveAmount) // passively delivered
      .add(deposits)
      .sub(withdrawals)
      .sub(deltas[0]); // spent
  }

  /**
   * This method calculates the balance expected to be credited in return for that
   * debited in another token according to the swapping price and is adjusted to
   * ignore numerical errors up to 2 decimal places.
   */
  function verifySwapConsistency(
    BimodalLib.Ledger storage ledger,
    ERC20[2] tokens,
    BimodalLib.Challenge challenge,
    uint256[2] LR,  // solhint-disable func-param-name-mixedcase
    uint256[2] deltas,
    uint256 passiveAmount,
    uint256 balance
  )
    private
    view
    returns (bool)
  {
    balance = calculateSwapConsistencyBalance(ledger, tokens[1], deltas, passiveAmount, balance);

    require(LR[1].sub(LR[0]) >= balance);

    uint256 taken = challenge.deltaHighestSpendings // sell amount
                  .sub(challenge.finalStateBalance.sub(challenge.initialStateBalance)); // refund
    uint256 given = LR[1].sub(LR[0]) // recipient allotment
                  .sub(balance); // authorized allotment

    return taken.mul(challenge.deltaHighestGains).div(100) >= challenge.deltaHighestSpendings.mul(given).div(100);
  }

  function answerSwapChallengeWithProofOfExclusiveBalanceAllotment(
    BimodalLib.Ledger storage ledger,
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
    ERC20 conduit = ERC20(address(keccak256(abi.encodePacked(tokens[0], tokens[1]))));
    BimodalLib.Challenge storage challenge = ledger.challengeBook[conduit][issuer][issuer];
    require(challenge.challengeType == BimodalLib.ChallengeType.SWAP_ENACTMENT);

    // Assert that the challenged swap belongs to the transition
    txSetRootChecksumDummy[2] = MerkleVerifier.swapOrderChecksum(
      tokens,
      challenge.trailIdentifier, // recipient trail
      challenge.deltaHighestSpendings, // sell amount
      challenge.deltaHighestGains, // buy amount
      balance, // starting balance
      challenge.deliveredTxNonce);

    require(MerkleVerifier.verifyProofOfMembership(
      transferMembershipTrail,
      txChain,
      txSetRootChecksumDummy[2], // order checksum
      txSetRootChecksumDummy[0]), 'M'); // txSetRoot

    // Require committed transition to include swap
    txSetRootChecksumDummy[2] = MerkleVerifier.activeStateUpdateChecksum(
      tokens[1],
      issuer,
      challenge.trailIdentifier,
      challenge.initialStateEon,
      txSetRootChecksumDummy[0], // txSetRoot
      lrDeltasPassiveMark[1]); // deltas

    if (balance != 2 ** 256 - 1) {
      require(verifySwapConsistency(
        ledger,
        tokens,
        challenge,
        lrDeltasPassiveMark[0],
        lrDeltasPassiveMark[1],
        lrDeltasPassiveMark[2][0],
        balance),
        'v');
    }

    // Assert that this transition was used to update the recipient's stake
    require(verifyProofOfExclusiveAccountBalanceAllotment(
        ledger,
        tokens[1],
        issuer,
        [txSetRootChecksumDummy[2], txSetRootChecksumDummy[1]], // activeStateChecksum, passiveChecksum
        challenge.trailIdentifier,
        [challenge.initialStateEon.add(1), lrDeltasPassiveMark[2][0], lrDeltasPassiveMark[2][1]],
        allotmentChain,
        membershipChain,
        values,
        lrDeltasPassiveMark[0]), // LR
      's');

    markChallengeAnswered(ledger, challenge);
  }

  // ========================================================================
  // ========================================================================
  // ========================================================================
  // ====================================  WITHDRAWAL Challenge
  // ========================================================================
  // ========================================================================
  // ========================================================================
  function slashWithdrawalWithProofOfMinimumAvailableBalance(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    address withdrawer,
    uint256[2] markerEonAvailable,
    bytes32[2] rs,
    uint8 v
  )
    public
    returns (uint256[2] amounts)
  {
    uint256 latestEon = ledger.currentEon();
    require(
      latestEon < markerEonAvailable[0].add(3),
      'm');

    bytes32 checksum = keccak256(abi.encodePacked(
      keccak256(abi.encodePacked(address(this))),
      keccak256(abi.encodePacked(token)),
      keccak256(abi.encodePacked(withdrawer)),
      markerEonAvailable[0],
      markerEonAvailable[1]
    ));

    require(withdrawer == BimodalLib.signedMessageECRECOVER(checksum, rs[0], rs[1], v));

    BimodalLib.Wallet storage entry = ledger.walletBook[token][withdrawer];
    BimodalLib.Withdrawal[] storage withdrawals = entry.withdrawals;

    for (uint32 i = 1; i <= withdrawals.length; i++) {
      BimodalLib.Withdrawal storage withdrawal = withdrawals[withdrawals.length.sub(i)];

      if (withdrawal.eon.add(1) < latestEon) {
        break;
      } else if (withdrawal.eon == latestEon.sub(1)) {
        amounts[0] = amounts[0].add(withdrawal.amount);
      } else if (withdrawal.eon == latestEon) {
        amounts[1] = amounts[1].add(withdrawal.amount);
      }
    }

    require(amounts[0].add(amounts[1]) > markerEonAvailable[1]);

    withdrawals.length = withdrawals.length.sub(i.sub(1)); // i >= 1

    if (amounts[1] > 0) {
      ledger.deductFromRunningPendingWithdrawals(token, latestEon, latestEon, amounts[1]);
      ledger.appendOperationToEonAccumulator(
        latestEon,
        token,
        withdrawer,
        BimodalLib.Operation.CANCELLATION,
        amounts[1]);
    }

    if (amounts[0] > 0) {
      ledger.deductFromRunningPendingWithdrawals(token, latestEon.sub(1), latestEon, amounts[0]);
      ledger.appendOperationToEonAccumulator(
        latestEon.sub(1),
        token, withdrawer,
        BimodalLib.Operation.CANCELLATION,
        amounts[0]);
    }
  }
}
