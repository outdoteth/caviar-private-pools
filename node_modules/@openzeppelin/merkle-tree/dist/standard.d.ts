import { MultiProof } from './core';
interface StandardMerkleTreeData<T extends any[]> {
    format: 'standard-v1';
    tree: string[];
    values: {
        value: T;
        treeIndex: number;
    }[];
    leafEncoding: string[];
}
export declare class StandardMerkleTree<T extends any[]> {
    private readonly tree;
    private readonly values;
    private readonly leafEncoding;
    private readonly hashLookup;
    private constructor();
    static of<T extends any[]>(values: T[], leafEncoding: string[]): StandardMerkleTree<T>;
    static load<T extends any[]>(data: StandardMerkleTreeData<T>): StandardMerkleTree<T>;
    dump(): StandardMerkleTreeData<T>;
    render(): string;
    get root(): string;
    entries(): Iterable<[number, T]>;
    validate(): void;
    leafHash(leaf: T): string;
    leafLookup(leaf: T): number;
    getProof(leaf: number | T): string[];
    getMultiProof(leaves: (number | T)[]): MultiProof<string, T>;
    verify(leaf: number | T, proof: string[]): boolean;
    private _verify;
    verifyMultiProof(multiproof: MultiProof<string, number | T>): boolean;
    private _verifyMultiProof;
    private validateValue;
    private getLeafHash;
}
export {};
//# sourceMappingURL=standard.d.ts.map