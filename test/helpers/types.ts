import {BigNumber} from 'ethers';

export type VersionTag = {release: BigNumber; build: BigNumber};

export enum Operation {
  Grant,
  Revoke,
  GrantWithCondition,
}
