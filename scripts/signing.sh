#!/bin/bash
# Reuse the sole local development certificate so TCC can recognize later builds.
# Override explicitly with CODE_SIGN_IDENTITY; '-' opts into ad-hoc signing.
if [[ -z "${CODE_SIGN_IDENTITY+x}" ]]; then
    CW_SIGNING_IDENTITIES=($(security find-identity -v -p codesigning | awk '/"Apple Development: / {print $2}'))
    if [[ ${#CW_SIGNING_IDENTITIES[@]} -eq 1 ]]; then
        export CODE_SIGN_IDENTITY="${CW_SIGNING_IDENTITIES[0]}"
    else
        export CODE_SIGN_IDENTITY="-"
    fi
fi
