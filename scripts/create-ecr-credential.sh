#!/bin/bash
export PYTHONUNBUFFERED=1
export PYTHONIOENCODING=utf-8
set -e

# If kli not installed
if ! command -v kli &> /dev/null
then
    python3.13 -m venv .venv
    # shellcheck disable=SC1091
    source .venv/bin/activate
    pip install -r requirements.txt
fi

random_suffix=$(openssl rand -base64 8 | tr -dc '[:alnum:]' | fold -w 8 | head -n 1)
geda_name="geda_${random_suffix}"

### Configure witness and schemas
witness_url=${WITNESS_URL:-"http://localhost:5642"}
schema_server_url=${SCHEMA_SERVER_URL:-"https://weboftrust.github.io"}
witness_aid=$(curl -s -D - -o /dev/null "$witness_url/oobi" | grep -i Keri-Aid | cut -d ' ' -f 2 | tr -d '\r')
keri_dir="$HOME/.keri" # TODO: If the user has access to /usr/local/var/keri/, that will be used by KERI instead
mkdir -p "$keri_dir/cf"
config_file="config_$random_suffix"
time=$(kli time)

cat << EOF > "$keri_dir/cf/$config_file.json"
{
  "dt": "$time",
  "iurls": [
    "$witness_url/oobi/$witness_aid"
  ],
  "durls": [
    "$schema_server_url/oobi/EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy",
    "$schema_server_url/oobi/EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao",
    "$schema_server_url/oobi/EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw",
    "$schema_server_url/oobi/EH6ekLjSr8V32WyFbGe1zXjTzFs9PkTYmupJ9H65O14g",
    "$schema_server_url/oobi/EKA57bKBKxr_kN7iN5i7lMUxpMG-s19dRcmov1iDxz-E",
    "$schema_server_url/oobi/EMhvwOlyEJ9kN4PrwCpr9Jsv7TxPhiYveZ0oP3lJzdEi",
    "$schema_server_url/oobi/ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY"
  ]
}
EOF

### Create Gleif External AID
kli init --name "$geda_name" --config-file "$config_file" --nopasscode

kli incept --name "$geda_name" --wit "$witness_aid" --icount 1 --ncount 1 --isith 1 --nsith 1 --transferable --alias geda --toad 1
kli ends add  --name "$geda_name" --alias geda --role mailbox --eid "$witness_aid"

geda_oobi=$(kli oobi generate --name "$geda_name" --alias geda --role witness | tail -n 1)
geda_aid=$(kli aid --name "$geda_name" --alias geda)

### Create QVI
qvi_name="qvi_${random_suffix}"
kli init --name "$qvi_name" --config-file "$config_file" --nopasscode
# Create a proxy AID for the creation for the delegated AID
kli incept --name "$qvi_name" --wit "$witness_aid" --icount 1 --ncount 1 --isith 1 --nsith 1 --transferable --alias qvi_proxy --toad 1

kli oobi resolve --name "$qvi_name" --oobi "$geda_oobi"
# Save the process id since this operation will not resolve until Gleif External AID has accepted the delegation
kli incept --name "$qvi_name" --wit "$witness_aid" --icount 1 --ncount 1 --isith 1 --nsith 1 --transferable --alias qvi --toad 1 --delpre "$geda_aid" --proxy qvi_proxy &
pids+=($!)

kli delegate confirm --name "$geda_name" --auto --alias geda  
wait "${pids[@]}"

kli ends add  --name "$qvi_name" --alias qvi --role mailbox --eid "$witness_aid"

qvi_oobi=$(kli oobi generate --name "$qvi_name" --alias qvi --role witness | tail -n 1)
qvi_aid=$(kli aid --name "$qvi_name" --alias qvi)

### QVI Credential

# QVI credential schema
schema_qvi_said="EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao"

kli oobi resolve --name "$geda_name" --oobi "$qvi_oobi"

kli vc registry incept --name "$geda_name" --alias geda --registry-name vlei

LEI_QVI="123"
# Create the QVI credential
kli vc create --name "$geda_name" --alias geda --registry-name vlei --data "{\"LEI\": \"$LEI_QVI\"}" --schema "$schema_qvi_said" --recipient "$qvi_aid"

qvi_credential_said=$(kli vc list --name "$geda_name" --alias geda --schema "$schema_qvi_said" --issued --said)

# Grant the QVI credential
kli ipex grant --name "$geda_name" --alias geda --recipient "$qvi_aid" --said "$qvi_credential_said"

# Wait for the grant to be received
kli ipex list --name "$qvi_name" --alias qvi --poll
grant_qvi_said=$(kli ipex list --name "$qvi_name" --alias qvi --type grant --said | tail -n 1)
# Admit the QVI credential
kli ipex admit --name "$qvi_name" --alias qvi --said "$grant_qvi_said"
# Wait for the QVI credential admittance to be received by GLEIF External
kli ipex list --name "$geda_name" --alias geda --poll

### Legal Entity

acme_name="acme_${random_suffix}"
kli init --name "$acme_name" --config-file "$config_file" --nopasscode

kli incept --name "$acme_name" --wit "$witness_aid" --icount 1 --ncount 1 --isith 1 --nsith 1 --transferable --alias acme --toad 1
kli ends add  --name "$acme_name" --alias acme --role mailbox --eid "$witness_aid"

acme_oobi=$(kli oobi generate --name "$acme_name" --alias acme --role witness | tail -n 1)
acme_aid=$(kli aid --name "$acme_name" --alias acme)

## Create Legal Entity credential

kli oobi resolve --name "$acme_name" --oobi "$qvi_oobi"
kli oobi resolve --name "$qvi_name" --oobi "$acme_oobi"

# Legal Entity credential schema
schema_le_said="ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY"

LEI_ACME="456"
kli vc registry incept --name "$qvi_name" --alias qvi --registry-name vlei
kli vc create --name "$qvi_name" --alias qvi --registry-name vlei --schema "$schema_le_said" --recipient "$acme_aid" \
  --data "{\"LEI\": \"$LEI_ACME\"}" \
  --edges "{\"d\": \"\", \"qvi\": {\"n\": \"$qvi_credential_said\", \"s\": \"$schema_qvi_said\"}}" \
  --rules '{"d": "EGZ97EjPSINR-O-KHDN_uw4fdrTxeuRXrqT5ZHHQJujQ",
  "usageDisclaimer": { 
    "l": "Usage of a valid, unexpired, and non-revoked vLEI Credential, as defined in the associated Ecosystem Governance Framework, does not assert that the Legal Entity is trustworthy, honest, reputable in its business dealings, safe to do business with, or compliant with any laws or that an implied or expressly intended purpose will be fulfilled."
  },
  "issuanceDisclaimer": {
    "l": "All information in a valid, unexpired, and non-revoked vLEI Credential, as defined in the associated Ecosystem Governance Framework, is accurate as of the date the validation process was complete. The vLEI Credential has been issued to the legal entity or person named in the vLEI Credential as the subject; and the qualified vLEI Issuer exercised reasonable care to perform the validation process set forth in the vLEI Ecosystem Governance Framework."
  }
}'

acme_credential_said=$(kli vc list --name "$qvi_name" --alias qvi --schema "$schema_le_said" --issued --said)

kli ipex grant --name "$qvi_name" --alias qvi --recipient "$acme_aid" --said "$acme_credential_said"

kli ipex list --name "$acme_name" --alias acme --poll
grant_acme_said=$(kli ipex list --name "$acme_name" --alias acme --type grant --said | tail -n 1)
kli ipex admit --name "$acme_name" --alias acme --said "$grant_acme_said"
kli ipex list --name "$qvi_name" --alias qvi --poll

### ACME Train conductor 

acme_conductor_name="acme_conductor_${random_suffix}"
kli init --name "$acme_conductor_name" --config-file "$config_file" --nopasscode

kli incept --name "$acme_conductor_name" --wit "$witness_aid" --icount 1 --ncount 1 --isith 1 --nsith 1 --transferable --alias acme_train_conductor --toad 1
kli ends add  --name "$acme_conductor_name" --alias acme_train_conductor --role mailbox --eid "$witness_aid"

acme_conductor_oobi=$(kli oobi generate --name "$acme_conductor_name" --alias acme_train_conductor --role witness | tail -n 1)
acme_conductor_aid=$(kli aid --name "$acme_conductor_name" --alias acme_train_conductor)

## Create Engagement Context Role credential for AMCE Train Conductor

kli oobi resolve --name "$acme_name" --oobi "$acme_conductor_oobi"
kli oobi resolve --name "$acme_conductor_name" --oobi "$acme_oobi"

# Engagement Context Role credential schema
schema_ecr_said="EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw"

kli vc registry incept --name "$acme_name" --alias acme --registry-name vlei
kli vc create --name "$acme_name" --alias acme --registry-name vlei --schema "$schema_ecr_said" --recipient "$acme_conductor_aid" --private \
  --data "{\"LEI\": \"$LEI_ACME\", \"engagementContextRole\":\"Train Conductor\", \"personLegalName\": \"Wayne Obstructor\"}" \
  --edges "{\"d\": \"\", \"le\": {\"n\": \"$acme_credential_said\", \"s\": \"$schema_le_said\"}}" \
  --rules '{"d": "EIfq_m1DI2IQ1MgHhUl9sq3IQ_PJP9WQ1LhbMscngDCB",
  "usageDisclaimer": {
    "l": "Usage of a valid, unexpired, and non-revoked vLEI Credential, as defined in the associated Ecosystem Governance Framework, does not assert that the Legal Entity is trustworthy, honest, reputable in its business dealings, safe to do business with, or compliant with any laws or that an implied or expressly intended purpose will be fulfilled."
  },
  "issuanceDisclaimer": {
    "l": "All information in a valid, unexpired, and non-revoked vLEI Credential, as defined in the associated Ecosystem Governance Framework, is accurate as of the date the validation process was complete. The vLEI Credential has been issued to the legal entity or person named in the vLEI Credential as the subject; and the qualified vLEI Issuer exercised reasonable care to perform the validation process set forth in the vLEI Ecosystem Governance Framework."
  },
  "privacyDisclaimer": {
    "l": "It is the sole responsibility of Holders as Issuees of an ECR vLEI Credential to present that Credential in a privacy-preserving manner using the mechanisms provided in the Issuance and Presentation Exchange (IPEX) protocol specification and the Authentic Chained Data Container (ACDC) specification. https://github.com/WebOfTrust/IETF-IPEX and https://github.com/trustoverip/tswg-acdc-specification."
  }
}'

acme_conductor_credential_said=$(kli vc list --name "$acme_name" --alias acme --schema "$schema_ecr_said" --issued --said)

kli ipex grant --name "$acme_name" --alias acme --recipient "$acme_conductor_aid" --said "$acme_conductor_credential_said"

kli ipex list --name "$acme_conductor_name" --alias acme_train_conductor --poll
grant_acme_conductor_said=$(kli ipex list --name "$acme_conductor_name" --alias acme_train_conductor --type grant --said | tail -n 1)
kli ipex admit --name "$acme_conductor_name" --alias acme_train_conductor --said "$grant_acme_conductor_said"
kli ipex list --name "$acme_name" --alias acme --poll


echo ""
echo "Successfully created ECR credential for ACME Train Conductor"
echo ""
echo "To view the credential run: "
echo ""
echo "kli vc list --name $acme_conductor_name --alias acme_train_conductor"
