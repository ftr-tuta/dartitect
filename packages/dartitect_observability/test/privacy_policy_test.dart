import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:test/test.dart';

void main() {
  test('classes validate and expose closest-first ancestry', () {
    final dataClass = ObservabilityDataClass.custom(
      'business.customer.contract_number',
    );

    expect(dataClass.hierarchy.map((value) => value.wireName), <String>[
      'business.customer.contract_number',
      'business.customer',
      'business',
    ]);
    expect(
      () => ObservabilityDataClass.custom('Customer Email'),
      throwsArgumentError,
    );
  });

  test('leaf rules search ancestors before decisions combine', () {
    final policy = ObservabilityPrivacyPolicy.fromProfile(
      profile: ObservabilityPrivacyProfile.diagnostic,
      overrideRuleAllow: <ObservabilityDataClass>{
        ObservabilityDataClass.httpHeader,
      },
      overrideRuleDeny: <ObservabilityDataClass>{ObservabilityDataClass.token},
    );

    final allowed = policy.explain(
      destination: ObservabilityDestinationKind.local,
      classes: <ObservabilityDataClass>{
        ObservabilityDataClass.custom('http.header.content_type.charset'),
      },
    );
    final denied = policy.explain(
      destination: ObservabilityDestinationKind.local,
      classes: <ObservabilityDataClass>{
        ObservabilityDataClass.httpHeader,
        ObservabilityDataClass.accessToken,
      },
    );

    expect(allowed.action, ObservabilityPrivacyAction.allow);
    expect(allowed.source, ObservabilityPrivacyDecisionSource.globalOverride);
    expect(denied.action, ObservabilityPrivacyAction.deny);
    expect(denied.winningClass, ObservabilityDataClass.accessToken);
  });

  test('named, destination, global, and profile precedence is explicit', () {
    final policy = ObservabilityPrivacyPolicy.fromProfile(
      profile: ObservabilityPrivacyProfile.strict,
      overrideRuleDeny: <ObservabilityDataClass>{
        ObservabilityDataClass.operation,
      },
      remoteOverrides: ObservabilityPrivacyOverrides(
        mask: <ObservabilityDataClass>{ObservabilityDataClass.runId},
      ),
      destinationOverrides: <ObservabilityDestinationPrivacyOverrides>[
        ObservabilityDestinationPrivacyOverrides(
          name: 'support',
          kind: ObservabilityDestinationKind.remote,
          rules: ObservabilityPrivacyOverrides(
            allow: <ObservabilityDataClass>{ObservabilityDataClass.runId},
          ),
        ),
      ],
    );

    final named = policy.explain(
      destination: ObservabilityDestinationKind.remote,
      destinationName: 'support',
      classes: <ObservabilityDataClass>{ObservabilityDataClass.runId},
    );
    final unnamed = policy.explain(
      destination: ObservabilityDestinationKind.remote,
      classes: <ObservabilityDataClass>{ObservabilityDataClass.runId},
    );

    expect(named.action, ObservabilityPrivacyAction.allow);
    expect(
      named.source,
      ObservabilityPrivacyDecisionSource.namedDestinationOverride,
    );
    expect(unnamed.action, ObservabilityPrivacyAction.mask);
    expect(
      unnamed.source,
      ObservabilityPrivacyDecisionSource.destinationOverride,
    );
  });

  test('conflicting rules and unsafe remote releases are rejected', () {
    expect(
      () => ObservabilityPrivacyPolicy.fromProfile(
        profile: ObservabilityPrivacyProfile.balanced,
        overrideRuleAllow: <ObservabilityDataClass>{
          ObservabilityDataClass.token,
        },
        overrideRuleDeny: <ObservabilityDataClass>{
          ObservabilityDataClass.token,
        },
      ),
      throwsArgumentError,
    );
    expect(
      () => ObservabilityPrivacyPolicy.fromProfile(
        profile: ObservabilityPrivacyProfile.balanced,
        remoteOverrides: ObservabilityPrivacyOverrides(
          allow: <ObservabilityDataClass>{ObservabilityDataClass.email},
        ),
      ),
      throwsArgumentError,
    );

    final accepted = ObservabilityPrivacyPolicy.fromProfile(
      profile: ObservabilityPrivacyProfile.balanced,
      remoteOverrides: ObservabilityPrivacyOverrides(
        allow: <ObservabilityDataClass>{ObservabilityDataClass.email},
      ),
      riskAcceptance: const ObservabilityRiskAcceptance.explicit(
        reason: 'Controlled QA environment with synthetic identities.',
      ),
    );
    expect(accepted.riskAcceptance, isNotNull);
  });

  test('masking is Unicode code-point safe and never reveals short values', () {
    const edges = ObservabilityMaskingPolicy.preserveEdges(
      visibleStart: 2,
      visibleEnd: 1,
    );
    const center = ObservabilityMaskingPolicy.preserveCenter(
      visibleCenter: 2,
      maskedStartUnits: 2,
      maskedEndUnits: 2,
    );

    expect(edges.mask('A😀BCDE'), 'A😀•••E');
    expect(edges.mask('A😀B'), '[REDACTED]');
    expect(center.mask('A😀BCDE'), '••BC••');
    expect(
      const ObservabilityMaskingPolicy.full().mask('secret'),
      '[REDACTED]',
    );
  });
}
