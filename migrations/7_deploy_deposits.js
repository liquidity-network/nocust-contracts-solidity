var BimodalLib = artifacts.require("BimodalLib");
var DepositLib = artifacts.require("DepositLib");

module.exports = async function(deployer, network, accounts) {
  deployer.link(BimodalLib, DepositLib);
  deployer.deploy(DepositLib);
};
