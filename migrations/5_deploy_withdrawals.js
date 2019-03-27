var BimodalLib = artifacts.require("BimodalLib");
var ChallengeLib = artifacts.require("ChallengeLib");
var WithdrawalLib = artifacts.require("WithdrawalLib");

module.exports = async function(deployer, network, accounts) {
  deployer.link(BimodalLib, WithdrawalLib);
  deployer.link(ChallengeLib, WithdrawalLib);
  deployer.deploy(WithdrawalLib);
};
