var BimodalLib = artifacts.require("BimodalLib");
var MerkleVerifier = artifacts.require("MerkleVerifier");
var ChallengeLib = artifacts.require("ChallengeLib");
var WithdrawalLib = artifacts.require("WithdrawalLib");
var RecoveryLib = artifacts.require("RecoveryLib");
var DepositLib = artifacts.require("DepositLib");
var NOCUSTCommitChain = artifacts.require("NOCUSTCommitChain");

module.exports = async function(deployer, network, accounts) {
  let hubAccount = accounts[0];
  let blocksPerEon = -1;
  if (network === 'development') {
    blocksPerEon = 180;
  } else if (network === 'ropsten') {
    blocksPerEon = 180;
  } else if (network === 'live') {
    blocksPerEon = 4320;
  }

  if (blocksPerEon === -1) {
    console.log("Unkown Network.")
    return;
  }

  console.log('================')
  console.log(`Using ${network} deployment configuration..`)
  console.log(`BLOCKS_PER_EON: ${blocksPerEon}`)
  console.log('================')

  // ganache-cli -d --allowUnlimitedContractSize --gasLimit 8000000
  deployer.link(BimodalLib, NOCUSTCommitChain);
  deployer.link(MerkleVerifier, NOCUSTCommitChain);
  deployer.link(ChallengeLib, NOCUSTCommitChain);
  deployer.link(WithdrawalLib, NOCUSTCommitChain);
  deployer.link(RecoveryLib, NOCUSTCommitChain);
  deployer.link(DepositLib, NOCUSTCommitChain);

  deployer.deploy(
    NOCUSTCommitChain,
    blocksPerEon,
    hubAccount);
};
