var BimodalLib = artifacts.require("BimodalLib");
var MerkleVerifier = artifacts.require("MerkleVerifier");
var ChallengeLib = artifacts.require("ChallengeLib");

module.exports = async function(deployer, network, accounts) {
  deployer.link(BimodalLib, ChallengeLib);
  deployer.link(MerkleVerifier, ChallengeLib);
  deployer.deploy(ChallengeLib);
};
