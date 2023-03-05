const fs = require("fs");
const path = require("path");
const { StandardMerkleTree } = require("@openzeppelin/merkle-tree");
const { defaultAbiCoder, parseEther } = require("ethers/lib/utils");

const generateMerkleProof = (tokenId, tokenWeight, tokenWeights) => {
  const tree = StandardMerkleTree.of(tokenWeights, ["uint256", "uint256"]);

  const proof = tree.getProof([tokenId, tokenWeight]);

  return proof;
};

const main = async () => {
  const tokenId = process.argv[2];
  const tokenWeight = process.argv[3];

  const tokenWeights = JSON.parse(
    fs.readFileSync(path.join(__dirname, "./token-weights.json"), {
      encoding: "utf8",
    })
  ).map(([tokenId, tokenWeight]) => [
    tokenId.toString(),
    parseEther(tokenWeight.toString()).toString(),
  ]);

  const merkleProof = generateMerkleProof(tokenId, tokenWeight, tokenWeights);

  process.stdout.write(defaultAbiCoder.encode(["bytes32[]"], [merkleProof]));
  process.exit();
};

main();

module.exports = { generateMerkleProof };
