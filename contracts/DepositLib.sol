pragma solidity ^0.4.24;

import "./ERC20.sol";
import "./BimodalLib.sol";
import "./SafeMath/SafeMathLib256.sol";

/**
 * This library defines the secure deposit method. The relevant data is recorded
 * on the parent chain to ascertain that a registered wallet would always be able
 * to ensure its commit chain state update consistency with the parent chain.
 */
library DepositLib {
  using SafeMathLib256 for uint256;
  using BimodalLib for BimodalLib.Ledger;
  // EVENTS
  event Deposit(address indexed token, address indexed recipient, uint256 amount);

  function deposit(
    BimodalLib.Ledger storage ledger,
    ERC20 token,
    address beneficiary,
    uint256 amount
  )
    public
    /* payable */
    /* onlyWhenContractUnpunished() */
  {
    uint256 eon = ledger.currentEon();

    uint256 value = msg.value;
    if (token != address(this)) {
      require(ledger.tokenToTrail[token] != 0,
        't');
      require(msg.value == 0,
        'm');
      require(token.transferFrom(beneficiary, this, amount),
        'f');
      value = amount;
    }

    BimodalLib.Wallet storage entry = ledger.walletBook[token][beneficiary];
    BimodalLib.AmountAggregate storage depositAggregate = entry.depositsKept[eon.mod(ledger.DEPOSITS_KEPT)];
    BimodalLib.addToAggregate(depositAggregate, eon, value);

    BimodalLib.AmountAggregate storage eonDeposits = ledger.deposits[token][eon.mod(ledger.EONS_KEPT)];
    BimodalLib.addToAggregate(eonDeposits, eon, value);

    ledger.appendOperationToEonAccumulator(eon, token, beneficiary, BimodalLib.Operation.DEPOSIT, value);

    emit Deposit(token, beneficiary, value);
  }
}
