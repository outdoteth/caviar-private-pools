const fs = require("fs");
const path = require("path");
const { StandardMerkleTree } = require("@openzeppelin/merkle-tree");
const { defaultAbiCoder, parseEther } = require("ethers/lib/utils");

const generateMerkleProof = (tokenIds, tokenWeights, allTokenWeights) => {
  const tree = StandardMerkleTree.of(allTokenWeights, ["uint256", "uint256"]);

  const proof = tree.getMultiProof(
    tokenIds.map((v, i) => [v, tokenWeights[i]])
  );

  return proof;
};

const main = async () => {
  const tokenIds = defaultAbiCoder
    .decode(["uint256[]"], process.argv[2])[0]
    .map((v) => v.toString());

  const tokenWeights = defaultAbiCoder
    .decode(["uint256[]"], process.argv[3])[0]
    .map((v) => v.toString());

  const allTokenWeights = JSON.parse(
    fs.readFileSync(path.join(__dirname, "./token-weights.json"), {
      encoding: "utf8",
    })
  ).map(([tokenId, tokenWeight]) => [
    tokenId.toString(),
    parseEther(tokenWeight.toString()).toString(),
  ]);

  const { proof, proofFlags } = generateMerkleProof(
    tokenIds,
    tokenWeights,
    allTokenWeights
  );

  process.stdout.write(
    defaultAbiCoder.encode(["bytes32[]", "bool[]"], [proof, proofFlags])
  );
  process.exit();
};

main();

module.exports = { generateMerkleProof };
