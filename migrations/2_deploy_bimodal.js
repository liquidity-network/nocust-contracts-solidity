var BimodalLib = artifacts.require("BimodalLib");

module.exports = async function(deployer, network, accounts) {
  deployer.deploy(BimodalLib);
};
