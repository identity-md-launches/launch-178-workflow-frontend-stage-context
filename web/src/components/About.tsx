import { explorerAddressUrl, type Deployment } from '../lib/deployment';

export function About({ deployment }: { deployment: Deployment }) {
  const { manifest, network, registry, token } = deployment;
  return (
    <section className="block" aria-labelledby="about-heading">
      <h2 id="about-heading">About, Limitations &amp; Deployment</h2>
      <div className="card stack">
        <p>
          <strong>Unofficial community experiment on the {network.name} testnet.</strong> IMD Oracle Challenges is an append-only
          public registry where anyone can record an evidence-backed challenge to an IMD oracle answer, anyone can append
          responses, and only the original challenger can withdraw their own challenge. It is not operated or endorsed by
          IMD.
        </p>
        <ul className="small" style={{ margin: 0, paddingLeft: '1.2rem' }}>
          <li>
            Every challenge is an <strong>unproven community claim</strong> attributed to the wallet that submitted it. A
            dispute&rsquo;s existence, its responses or its withdrawal say nothing about whether the oracle answer was right.
          </li>
          <li>
            The registry is not an oracle, an adjudicator or an appeals process. It cannot reverse IMD decisions, penalise
            agents or prove a challenged answer wrong. The only statuses are <strong>Open</strong> and{' '}
            <strong>Withdrawn</strong>.
          </li>
          <li>
            Data fetched from the IMD API is shown exactly as the API advertised it. This site does not verify
            signatures and does not judge answers; it only hashes the exact bytes so a reader can later compare them.
          </li>
          <li>
            <strong>Two chains, kept apart:</strong> registry transactions happen on {network.name} (chain {network.chainId}).
            The <em>source chain</em> shown on each card is the chain the challenged oracle request was about, as
            claimed by the challenger. This site never transacts on a source chain and never on mainnet.
          </li>
          <li>
            Everything stored is user-submitted and unmoderated. Text is rendered as plain text; only validated{' '}
            <code>https://</code> and <code>ipfs://</code> URIs are linked. Wallet counts are not person counts.
          </li>
          <li>
            Evidence hosting is external: the registry stores a URI and a keccak256 commitment. Choosing a local file here
            only computes its hash in your browser; nothing is uploaded or hosted by this site.
          </li>
          <li>
            No fees, bonds, rewards, staking, votes, admin, upgrade or token dependency. OCTEST is a separate {network.name} test
            token and is never required.
          </li>
        </ul>
        <details>
          <summary>Deployment configuration (loaded at runtime from imd-deployment.json)</summary>
          <dl className="kv small">
            <dt>Launch id</dt>
            <dd>
              <code translate="no">{manifest.launchId}</code>
            </dd>
            <dt>Registry chain</dt>
            <dd>
              {network.name} (chain <span className="num">{manifest.chainId}</span>, testnet)
            </dd>
            <dt>Source commit</dt>
            <dd>
              <code translate="no" className="break">
                {manifest.sourceCommit}
              </code>
            </dd>
            <dt>Attestation hash</dt>
            <dd>
              <code translate="no" className="break">
                {manifest.attestationHash}
              </code>
            </dd>
            <dt>{registry.name}</dt>
            <dd>
              <a href={explorerAddressUrl(network, registry.address)} target="_blank" rel="noopener noreferrer" className="break">
                <code translate="no">{registry.address}</code>
              </a>
              <br />
              ABI <code translate="no" className="break">{registry.abiHash}</code>{' '}
              <span className="badge badge-ok">verified in browser</span>
            </dd>
            <dt>{token.name}</dt>
            <dd>
              <a href={explorerAddressUrl(network, token.address)} target="_blank" rel="noopener noreferrer" className="break">
                <code translate="no">{token.address}</code>
              </a>
              <br />
              ABI <code translate="no" className="break">{token.abiHash}</code>{' '}
              <span className="badge badge-ok">verified in browser</span>
            </dd>
            <dt>Public RPCs</dt>
            <dd>
              {network.rpcUrls.map((u) => (
                <div key={u}>
                  <code translate="no" className="break">
                    {u}
                  </code>
                </div>
              ))}
            </dd>
            <dt>Explorer</dt>
            <dd>
              <a href={network.explorer} target="_blank" rel="noopener noreferrer">
                {network.explorer}
              </a>
            </dd>
            <dt>Faucets (reference)</dt>
            <dd>
              {(network.faucets ?? []).map((u) => (
                <div key={u}>
                  <a href={u} target="_blank" rel="noopener noreferrer" className="break">
                    {u}
                  </a>
                </div>
              ))}
            </dd>
            <dt>Manifest file</dt>
            <dd>
              <a href="./imd-deployment.json" target="_blank" rel="noopener noreferrer">
                imd-deployment.json
              </a>{' '}
              · ABIs: <a href={`./${registry.abiPath}`}>{registry.abiPath}</a>, <a href={`./${token.abiPath}`}>{token.abiPath}</a>
            </dd>
          </dl>
        </details>
      </div>
    </section>
  );
}
