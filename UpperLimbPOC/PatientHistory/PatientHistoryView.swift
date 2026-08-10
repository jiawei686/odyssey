import RealityKit
import SwiftUI

struct PatientHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRecordID = DemoVisitRecord.records.last!.id

    private var selectedRecord: DemoVisitRecord {
        DemoVisitRecord.records.first { $0.id == selectedRecordID }
            ?? DemoVisitRecord.records[0]
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 760 {
                HStack(spacing: 0) {
                    timeline
                        .frame(width: 310)

                    Divider()

                    recordDetail
                }
            } else {
                VStack(spacing: 0) {
                    timeline
                        .frame(height: 250)

                    Divider()

                    recordDetail
                }
            }
        }
        .navigationTitle("Treatment History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Close", systemImage: "xmark") {
                    dismiss()
                }
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Demo patient", systemImage: "person.crop.circle")
                    .font(.headline)
                Text("Right distal radius recovery")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(22)

            Divider()

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(DemoVisitRecord.records.reversed()) { record in
                        timelineRow(record)
                    }
                }
                .padding(14)
            }

            Divider()

            Label(
                "Synthetic demonstration records",
                systemImage: "checkmark.shield"
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(18)
        }
        .background(.thinMaterial)
    }

    private func timelineRow(_ record: DemoVisitRecord) -> some View {
        Button {
            selectedRecordID = record.id
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(record.tint.opacity(0.18))
                    Text("\(record.stage)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(record.tint)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.phase)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(record.date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(record.status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(record.tint)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selectedRecordID == record.id
                    ? record.tint.opacity(0.14)
                    : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        selectedRecordID == record.id
                            ? record.tint.opacity(0.6)
                            : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Stage \(record.stage), \(record.phase), \(record.date), \(record.status)"
        )
    }

    private var recordDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "Stage \(selectedRecord.stage) of 3",
                            systemImage: selectedRecord.symbol
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedRecord.tint)

                        Text(selectedRecord.title)
                            .font(.title.bold())

                        Text("\(selectedRecord.date) at \(selectedRecord.time)")
                            .foregroundStyle(.secondary)

                        Text(selectedRecord.department)
                            .font(.subheadline.weight(.semibold))
                    }

                    Spacer()

                    Text(selectedRecord.status)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selectedRecord.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedRecord.tint.opacity(0.14),
                            in: Capsule()
                        )
                }

                HistoryModelPreview(resourceName: selectedRecord.modelName)
                    .id(selectedRecord.modelName)
                    .frame(maxWidth: .infinity)
                    .frame(height: 380)

                HStack(spacing: 18) {
                    metadata(
                        title: "Imaging",
                        value: "3D CT reconstruction",
                        symbol: "cube.transparent"
                    )
                    metadata(
                        title: "Region",
                        value: "Right wrist and distal forearm",
                        symbol: "hand.raised"
                    )
                    metadata(
                        title: "Record",
                        value: "Synthetic demo",
                        symbol: "doc.text"
                    )
                }

                reportSection(
                    title: "Apple Intelligence summary",
                    symbol: "apple.intelligence",
                    text: selectedRecord.summary,
                    annotation: "Prewritten demonstration content"
                )

                reportSection(
                    title: "Consultation record",
                    symbol: "waveform.and.mic",
                    text: selectedRecord.consultation,
                    annotation: "Synthetic visit transcript summary"
                )

                reportSection(
                    title: "Imaging report",
                    symbol: "viewfinder",
                    text: selectedRecord.imagingReport,
                    annotation: "Not reviewed for clinical use"
                )

                reportSection(
                    title: "Plan at this visit",
                    symbol: "list.clipboard",
                    text: selectedRecord.plan,
                    annotation: nil
                )

                Label(
                    "Demo only - not a diagnosis, medical record, or treatment recommendation",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.bottom, 12)
            }
            .padding(28)
        }
    }

    private func metadata(
        title: String,
        value: String,
        symbol: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reportSection(
        title: String,
        symbol: String,
        text: String,
        annotation: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack {
                Label(title, systemImage: symbol)
                    .font(.title3.bold())

                Spacer()

                if let annotation {
                    Text(annotation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(text)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }
}

private struct HistoryModelPreview: View {
    let resourceName: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)

            if let url = Bundle.main.url(
                forResource: resourceName,
                withExtension: "usdz"
            ) {
                Model3D(url: url) { model in
                    model
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(.top, 24)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 72)
                } placeholder: {
                    ProgressView("Loading 3D CT")
                        .controlSize(.large)
                }
            } else {
                VStack(spacing: 12) {
                    Label("3D model unavailable", systemImage: "cube.transparent")
                        .foregroundStyle(.secondary)
                }
            }

            VStack {
                HStack {
                    Label("3D CT model", systemImage: "view.3d")
                        .font(.caption.weight(.semibold))
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())

                    Spacer()
                }
                Spacer()
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityLabel("Three-dimensional CT demonstration model")
    }
}

private struct DemoVisitRecord: Identifiable {
    let id: Int
    let stage: Int
    let phase: String
    let title: String
    let date: String
    let time: String
    let department: String
    let status: String
    let symbol: String
    let tint: Color
    let modelName: String
    let summary: String
    let consultation: String
    let imagingReport: String
    let plan: String

    static let records = [
        DemoVisitRecord(
            id: 1,
            stage: 1,
            phase: "Injury",
            title: "Initial injury assessment",
            date: "14 Jan 2026",
            time: "09:30",
            department: "Emergency and Orthopaedic Clinic",
            status: "Acute",
            symbol: "cross.case.fill",
            tint: .orange,
            modelName: "stage1",
            summary: "The patient attended after a fall onto the right hand. The recorded discussion describes immediate wrist pain, swelling, and difficulty gripping. The demonstration CT reconstruction is consistent with an acute distal-radius injury. No numbness or colour change was reported during the sample consultation.",
            consultation: "Patient reports falling forward at home and landing on the palm. Pain is concentrated around the right wrist and increases with rotation. Fingers remain warm and mobile. This entry represents a condensed example of the recorded clinician-patient conversation.",
            imagingReport: "Demonstration model shows cortical disruption at the distal radius with local displacement and surrounding soft-tissue swelling. Carpal alignment is preserved in this synthetic report. Findings require clinician correlation in any real case.",
            plan: "Wrist support was documented, with orthopaedic follow-up and repeat imaging planned. The sample record also notes return precautions for increasing pain, numbness, colour change, or swelling."
        ),
        DemoVisitRecord(
            id: 2,
            stage: 2,
            phase: "Recovery",
            title: "Healing progress review",
            date: "18 Feb 2026",
            time: "14:10",
            department: "Orthopaedic Follow-up",
            status: "Healing",
            symbol: "bandage.fill",
            tint: .blue,
            modelName: "stage2",
            summary: "At the five-week review, the sample consultation records lower resting pain and improved finger use. The follow-up 3D reconstruction demonstrates interval healing around the distal radius. Mild stiffness remains, without new sensory symptoms in the synthetic history.",
            consultation: "Patient reports that swelling has reduced and sleep is no longer interrupted by pain. Wrist movement remains limited after immobilisation, while finger motion is comfortable. No new fall, numbness, or weakness is recorded.",
            imagingReport: "Demonstration follow-up model shows developing callus around the prior distal-radius injury and maintained interval alignment. The fracture line remains partly visible. This is prewritten demo content and has not been clinically interpreted.",
            plan: "The sample plan documents continued protection of the wrist, gradual movement within the treating clinician's limits, and another review before increasing load."
        ),
        DemoVisitRecord(
            id: 3,
            stage: 3,
            phase: "Rehabilitation",
            title: "Functional recovery review",
            date: "08 Apr 2026",
            time: "10:45",
            department: "Rehabilitation Clinic",
            status: "Rehabilitating",
            symbol: "figure.strengthtraining.traditional",
            tint: .green,
            modelName: "stage3",
            summary: "The latest sample visit records no pain at rest and improving daily use of the right hand. The 3D reconstruction demonstrates advanced healing and remodelling. Mild wrist stiffness and reduced endurance remain the main rehabilitation concerns described in the consultation.",
            consultation: "Patient can now manage dressing, light meal preparation, and keyboard work. Prolonged lifting still causes fatigue, and end-range wrist extension feels tight. The recorded goals are comfortable daily activity and a gradual return to recreational exercise.",
            imagingReport: "Demonstration model shows bridging healing and remodelling at the distal radius with stable alignment. No new osseous injury is represented in this synthetic stage. Real imaging must be reviewed by a qualified clinician.",
            plan: "The demo record describes progressive supervised mobility and strengthening, monitoring symptoms as activity increases, and a final functional review if stiffness or pain persists."
        )
    ]
}
