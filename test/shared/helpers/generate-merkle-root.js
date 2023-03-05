const fs = require("fs");
const path = require("path");
const { StandardMerkleTree } = require("@openzeppelin/merkle-tree");
const { parseEther } = require("ethers/lib/utils");

const generateMerkleRoot = () => {
  const tokenWeights = JSON.parse(
    fs.readFileSync(path.join(__dirname, "./token-weights.json"), {
      encoding: "utf8",
    })
  ).map(([tokenId, tokenWeight]) => [
    tokenId.toString(),
    parseEther(tokenWeight.toString()).toString(),
  ]);

  const tree = StandardMerkleTree.of(tokenWeights, ["uint256", "uint256"]);

  return tree.root;
};

const main = async () => {
  const merkleRoot = generateMerkleRoot();

  process.stdout.write(merkleRoot);
  process.exit();
};

main();
