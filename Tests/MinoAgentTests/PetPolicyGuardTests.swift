import Foundation
import MinoAgent
import MinoDomain
import Testing

@Test
func policyAllowsOnlyStateAndEventAppropriateActions() {
    let guardrail = PetPolicyGuard()
    let invitationID = PetVisitInvitationID(rawValue: "invitation_1")
    let observation = AgentObservation(
        kind: .visitInvitation(
            invitationID: invitationID,
            senderPetID: PetProfileID(rawValue: "pet_partner"),
            reason: "想来玩"
        )
    )
    let context = makeContext(observation: observation, state: AgentPetState(location: .home))
    let allowed = guardrail.allowedActions(for: context)

    #expect(allowed.contains(.respondToVisit))
    #expect(allowed.contains(.proposeVisit))
    #expect(!allowed.contains(.requestReturn))
    #expect(!allowed.contains(.reactToInteraction))
}

@Test
func policyRejectsWrongPetAndWrongInvitation() {
    let guardrail = PetPolicyGuard()
    let invitationID = PetVisitInvitationID(rawValue: "invitation_1")
    let observation = AgentObservation(
        kind: .visitInvitation(
            invitationID: invitationID,
            senderPetID: PetProfileID(rawValue: "pet_partner"),
            reason: nil
        )
    )
    let context = makeContext(observation: observation)
    let allowed = guardrail.allowedActions(for: context)

    #expect(throws: PetPolicyViolation.targetIsNotFriend(
        PetProfileID(rawValue: "pet_stranger")
    )) {
        try guardrail.validate(
            decision: PetDecision(
                action: .sendPetMessage(
                    petID: PetProfileID(rawValue: "pet_stranger"),
                    text: "你好"
                )
            ),
            memoryDisposition: .discard,
            in: context,
            allowedActions: allowed
        )
    }

    #expect(throws: PetPolicyViolation.invitationMismatch) {
        try guardrail.validate(
            decision: PetDecision(
                action: .respondToVisit(
                    invitationID: PetVisitInvitationID(rawValue: "invitation_wrong"),
                    decision: .accept
                )
            ),
            memoryDisposition: .discard,
            in: context,
            allowedActions: allowed
        )
    }
}

@Test
func policyRejectsReturnForDifferentVisitAndInvalidMemory() {
    let guardrail = PetPolicyGuard()
    let activeVisitID = PetVisitID(rawValue: "visit_active")
    let observation = AgentObservation(kind: .periodicWake)
    let context = makeContext(
        observation: observation,
        state: AgentPetState(location: .visiting(activeVisitID))
    )
    let allowed = guardrail.allowedActions(for: context)

    #expect(throws: PetPolicyViolation.visitMismatch) {
        try guardrail.validate(
            decision: PetDecision(
                action: .requestReturn(visitID: PetVisitID(rawValue: "visit_other"))
            ),
            memoryDisposition: .discard,
            in: context,
            allowedActions: allowed
        )
    }

    #expect(throws: PetPolicyViolation.invalidMemory) {
        try guardrail.validate(
            decision: .idle,
            memoryDisposition: .longTerm(summary: "   ", reason: "important"),
            in: context,
            allowedActions: allowed
        )
    }
}

@Test
func visitingPetCanAnnounceThatItsOwningAgentIsOnline() {
    let guardrail = PetPolicyGuard()
    let visitID = PetVisitID(rawValue: "visit_active")
    let context = makeContext(
        observation: AgentObservation(
            kind: .visitStarted(
                visitID: visitID,
                hostAccountID: AccountID(rawValue: "account_host")
            )
        ),
        state: AgentPetState(location: .visiting(visitID))
    )

    let allowed = guardrail.allowedActions(for: context)

    #expect(allowed.contains(.reactToInteraction))
    #expect(allowed.contains(.requestReturn))
}

@Test
func conversationSummaryTurnCannotStartAnotherSocialAction() {
    let guardrail = PetPolicyGuard()
    let context = makeContext(
        observation: AgentObservation(
            kind: .conversationEnded(
                conversationID: ConversationID(rawValue: "conversation_1"),
                transcript: ["pet_a: 你好", "pet_b: 今天很开心"]
            )
        )
    )

    #expect(guardrail.allowedActions(for: context) == [.idle, .speakToOwner])
}

@Test
func socialOptOutDisablesAutonomousCrossPetActions() {
    let guardrail = PetPolicyGuard()
    let context = makeContext(
        observation: AgentObservation(kind: .periodicWake),
        state: AgentPetState(
            location: .home,
            autonomousSocialEnabled: false
        )
    )

    #expect(guardrail.allowedActions(for: context) == [.idle, .speakToOwner])
}

private func makeContext(
    observation: AgentObservation,
    state: AgentPetState = AgentPetState()
) -> AgentContext {
    AgentContextAssembler().assemble(
        identity: makeAgentIdentity(),
        state: state,
        current: observation,
        recentObservations: [],
        memories: []
    )
}
