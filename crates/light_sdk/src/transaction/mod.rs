use std::collections::BTreeMap;

use borsh::BorshSerialize;
use namada_sdk::address::Address;
use namada_sdk::chain::ChainId;
use namada_sdk::hash::Hash;
use namada_sdk::key::common;
use namada_sdk::time::DateTimeUtc;
use namada_sdk::token::DenominatedAmount;
use namada_sdk::tx::data::{Fee, GasLimit};
use namada_sdk::tx::{Authorization, Section, Signer, Tx};

pub mod account;
pub mod bridge;
pub mod governance;
pub mod ibc;
pub mod pgf;
pub mod pos;
pub mod transfer;

/// Generic arguments required to construct a transaction
#[derive(Debug, Clone)]
pub struct GlobalArgs {
    pub expiration: Option<DateTimeUtc>,
    pub code_hash: Hash,
    pub chain_id: ChainId,
}

pub(in crate::transaction) fn build_tx(
    GlobalArgs {
        expiration,
        code_hash,
        chain_id,
    }: GlobalArgs,
    data: impl BorshSerialize,
    code_tag: String,
) -> Tx {
    let mut inner_tx = Tx::new(chain_id, expiration);

    inner_tx.header.timestamp =
        DateTimeUtc::now();
    inner_tx.add_code_from_hash(code_hash, Some(code_tag));
    inner_tx.add_data(data);

    inner_tx
}

pub(in crate::transaction) fn get_sign_bytes(tx: &Tx) -> Vec<Hash> {
    vec![tx.raw_header_hash()]
}

pub(in crate::transaction) fn get_wrapper_sign_bytes(tx: &Tx) -> Hash {
    let targets = tx.sechashes();
    // Commit to the given targets
    let partial = Authorization {
        targets,
        signer: Signer::PubKeys(vec![]),
        signatures: BTreeMap::new(),
    };
    partial.get_raw_hash()
}

pub(in crate::transaction) fn attach_raw_signatures(
    mut tx: Tx,
    signer: common::PublicKey,
    signature: common::Signature,
) -> Tx {
    tx.protocol_filter();
    tx.add_section(Section::Authorization(Authorization {
        targets: vec![tx.raw_header_hash()],
        signer: Signer::PubKeys(vec![signer]),
        signatures: [(0, signature)].into_iter().collect(),
    }));
    tx
}

pub(in crate::transaction) fn attach_fee(
    mut tx: Tx,
    fee: DenominatedAmount,
    token: Address,
    fee_payer: common::PublicKey,
    gas_limit: GasLimit,
) -> Tx {
    tx.add_wrapper(
        Fee {
            amount_per_gas_unit: fee,
            token,
        },
        fee_payer,
        gas_limit,
    );
    tx
}

pub(in crate::transaction) fn attach_fee_signature(
    mut tx: Tx,
    signer: common::PublicKey,
    signature: common::Signature,
) -> Tx {
    tx.protocol_filter();
    tx.add_section(Section::Authorization(Authorization {
        targets: tx.sechashes(),
        signer: Signer::PubKeys(vec![signer]),
        signatures: [(0, signature)].into_iter().collect(),
    }));
    tx
}
