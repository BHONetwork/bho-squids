import { Command, Option } from 'commander';
import chalk from 'chalk';
import fs from 'node:fs';
import path from 'node:path';
import { ApiPromise, WsProvider } from '@polkadot/api';
import { Keyring } from '@polkadot/keyring';
import { CodePromise, ContractPromise } from '@polkadot/api-contract';
import {
  uniqueNamesGenerator,
  names,
  adjectives,
  Config,
} from 'unique-names-generator';
import initials from 'initials';
import BN from 'bn.js';
import { CodeSubmittableResult } from '@polkadot/api-contract/base';

const uniqueNameConfig: Config = {
  dictionaries: [adjectives, names],
  separator: ' ',
};

const GAS_LIMIT = 4_000_000_000;

const program = new Command();

program
  .command('create-bhc22')
  .description('Create a BHC22 assets')
  .addOption(
    new Option('--chainEndpoint <string>', 'Chain endpoint').default(
      'ws://localhost:9944'
    )
  )
  .addOption(new Option('--name <string>', 'Name of token'))
  .addOption(new Option('--symbol <string>', 'Symbol of token'))
  .addOption(
    new Option('--decimals <number>', 'Decimals of token')
      .default(18)
      .argParser(parseInt)
  )
  .addOption(
    new Option('--deployerUri <string>', 'Deployer seed phrase').default(
      '//Alice'
    )
  )
  .addOption(
    new Option('--totalSupply <number>', 'Total supply accounted for decimals')
      .default(1)
      .argParser(parseInt)
  )
  .action(async (options) => {
    const bhc22Source = fs.readFileSync(
      path.join(__dirname, './fixtures/contracts/bhc22_contract.contract'),
      'utf-8'
    );

    console.log(chalk.blue('Initializing Chain API...'));
    const api = await initChainApi(options.chainEndpoint);
    console.log(chalk.blue('Chain API Initialized...'));

    const keyring = new Keyring({ type: 'sr25519' });
    const deployerKeypair = keyring.createFromUri(options.deployerUri);

    const tokenName = options.name ?? uniqueNamesGenerator(uniqueNameConfig);
    const tokenSymbol = initials(tokenName);
    const tokenDecimals = options.decimals;
    const tokenSupply = new BN(options.totalSupply).mul(
      new BN(10).pow(new BN(tokenDecimals))
    );

    console.log('\n');
    console.log(chalk.blue(`Token name: ${tokenName}`));
    console.log(chalk.blue(`Token symbol: ${tokenSymbol}`));
    console.log(chalk.blue(`Token decimals: ${tokenDecimals}`));

    const bhc22Code = new CodePromise(api, bhc22Source, '');
    console.log('\n');
    console.log(chalk.blue(`Deploying token...`));

    const contract = await new Promise<ContractPromise>((resolve, reject) => {
      let unsub;
      const tx = bhc22Code.tx.new(
        { gasLimit: GAS_LIMIT },
        tokenName,
        tokenSymbol,
        tokenDecimals,
        tokenSupply
      );

      tx.signAndSend(
        deployerKeypair,
        ({
          status,
          dispatchError,
          contract,
        }: CodeSubmittableResult<'promise'>) => {
          if (status.isInBlock) {
            if (dispatchError) {
              reject(dispatchError.toString());
            } else {
              resolve(contract);
            }

            return unsub();
          }
        }
      )
        .then((_unsub) => {
          unsub = _unsub;
        })
        .catch(reject);
    });

    console.log(
      chalk.blue(`Contract deployed at ${contract.address.toString()}`)
    );
  });

program
  .parseAsync()
  .then(() => {
    process.exit(0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });

async function initChainApi(url: string): Promise<ApiPromise> {
  const api = await ApiPromise.create({ provider: new WsProvider(url) });
  return api;
}
