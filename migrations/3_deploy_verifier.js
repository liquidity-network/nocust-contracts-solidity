var MerkleVerifier = artifacts.require("MerkleVerifier");
var MerkleVerifierProxy = artifacts.require("MerkleVerifierProxy");

module.exports = async function(deployer, network, accounts) {
  await deployer.deploy(MerkleVerifier);
  deployer.link(MerkleVerifier, MerkleVerifierProxy);

  deployer.deploy(MerkleVerifierProxy);
};
