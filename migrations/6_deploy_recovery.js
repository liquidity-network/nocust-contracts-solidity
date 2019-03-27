var BimodalLib = artifacts.require("BimodalLib");
var ChallengeLib = artifacts.require("ChallengeLib");
var RecoveryLib = artifacts.require("RecoveryLib");

module.exports = async function(deployer, network, accounts) {
  deployer.link(BimodalLib, RecoveryLib);
  deployer.link(ChallengeLib, RecoveryLib);
  deployer.deploy(RecoveryLib);
};
