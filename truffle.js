module.exports = {
  networks: {
    development: {
      host: "localhost",
      port: 8545,
      network_id: "*" // Match any network id
    },
    ropsten: {
      host: "localhost",
      port: 8545,
      network_id: 3
    },
    live: {
      host: "localhost",
      port: 8545,
      network_id: 1
    }
  },
  compilers: {
   solc: {
     version: "0.4.24"
   }
  },
  solc: {
    optimizer: {
      enabled: true,
      runs: 200
    }
  }
};
