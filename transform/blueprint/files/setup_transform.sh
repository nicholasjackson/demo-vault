#! /bin/sh

vault secrets enable transform

vault write transform/role/payments transformations=ccn-fpe

vault write transform/transformation/ccn-fpe \
type=fpe \
template=ccn \
tweak_source=internal \
allowed_roles=payments

vault write transform/template/ccn \
type=regex \
pattern='\d{4}-\d{2}(\d{2})-(\d{4})-(\d{4})' \
alphabet=numerics

vault write transform/alphabet/numerics \
alphabet="0123456789"