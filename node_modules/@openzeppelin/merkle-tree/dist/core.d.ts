import { Bytes } from './bytes';
export declare function makeMerkleTree(leaves: Bytes[]): Bytes[];
export declare function getProof(tree: Bytes[], index: number): Bytes[];
export declare function processProof(leaf: Bytes, proof: Bytes[]): Bytes;
export interface MultiProof<T, L = T> {
    leaves: L[];
    proof: T[];
    proofFlags: boolean[];
}
export declare function getMultiProof(tree: Bytes[], indices: number[]): MultiProof<Bytes>;
export declare function processMultiProof(multiproof: MultiProof<Bytes>): Bytes;
export declare function isValidMerkleTree(tree: Bytes[]): boolean;
export declare function renderMerkleTree(tree: Bytes[]): string;
//# sourceMappingURL=core.d.ts.map