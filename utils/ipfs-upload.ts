import {BytesLike, ethers} from 'ethers';
import IPFS from 'ipfs-http-client';

export async function uploadToIPFS(
  content: string,
  testing: boolean = true
): Promise<string> {
  const client = IPFS.create({
    url: testing
      ? 'https://testing-ipfs-0.aragon.network/api/v0'
      : 'https://ipfs-0.aragon.network/api/v0',
    headers: {
      'X-API-KEY': 'b477RhECf8s8sdM7XrkLBs2wHc4kCMwpbcFC55Kt',
    },
  });

  const cid = await client.add(content);
  await client.pin.add(cid.cid);
  return cid.path;
}

export function toHex(input: string): BytesLike {
  return ethers.utils.hexlify(ethers.utils.toUtf8Bytes(input));
}
