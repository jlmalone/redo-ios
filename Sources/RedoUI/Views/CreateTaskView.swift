import SwiftUI

/// Create task sheet with Matrix theme
public struct CreateTaskView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var priority = 3
    @State private var storyPoints: Float = 1.0
    @State private var frequencyDays = 7
    @State private var isCreating = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Color.matrixBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .matrixSpacingLarge) {
                        // Title field
                        VStack(alignment: .leading, spacing: .matrixSpacingSmall) {
                            Text("Title")
                                .font(.matrixCallout)
                                .foregroundColor(.matrixNeon)

                            TextField("What needs to be done?", text: $title)
                                .font(.matrixBody)
                                .foregroundColor(.matrixTextPrimary)
                                .padding()
                                .background(Color.matrixBackgroundSecondary)
                                .cornerRadius(.matrixCornerRadius)
                                .matrixBorder()
                        }

                        // Description field
                        VStack(alignment: .leading, spacing: .matrixSpacingSmall) {
                            Text("Description")
                                .font(.matrixCallout)
                                .foregroundColor(.matrixNeon)

                            TextEditor(text: $description)
                                .font(.matrixBody)
                                .foregroundColor(.matrixTextPrimary)
                                .scrollContentBackground(.hidden)
                                .frame(height: 100)
                                .padding(8)
                                .background(Color.matrixBackgroundSecondary)
                                .cornerRadius(.matrixCornerRadius)
                                .matrixBorder()
                        }

                        // Priority selector
                        VStack(alignment: .leading, spacing: .matrixSpacingSmall) {
                            Text("Priority")
                                .font(.matrixCallout)
                                .foregroundColor(.matrixNeon)

                            HStack(spacing: .matrixSpacingSmall) {
                                ForEach([1, 2, 3, 4, 5], id: \.self) { p in
                                    PriorityButton(
                                        priority: p,
                                        isSelected: priority == p,
                                        action: { priority = p }
                                    )
                                }
                            }
                        }

                        // Story points slider
                        VStack(alignment: .leading, spacing: .matrixSpacingSmall) {
                            HStack {
                                Text("Story Points")
                                    .font(.matrixCallout)
                                    .foregroundColor(.matrixNeon)

                                Spacer()

                                Text("\(Int(storyPoints))")
                                    .font(.matrixBodyBold)
                                    .foregroundColor(.matrixTextPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.matrixNeon.opacity(0.15))
                                    .cornerRadius(6)
                            }

                            Slider(value: $storyPoints, in: 1...13, step: 1)
                                .tint(.matrixNeon)
                        }
                        .padding()
                        .background(Color.matrixBackgroundSecondary)
                        .cornerRadius(.matrixCornerRadius)
                        .matrixBorder()

                        // Frequency selector
                        VStack(alignment: .leading, spacing: .matrixSpacingSmall) {
                            Text("Recurrence")
                                .font(.matrixCallout)
                                .foregroundColor(.matrixNeon)

                            Picker("Frequency", selection: $frequencyDays) {
                                Text("One-time").tag(0)
                                Text("Daily").tag(1)
                                Text("Weekly").tag(7)
                                Text("Bi-weekly").tag(14)
                                Text("Monthly").tag(30)
                            }
                            .pickerStyle(.segmented)
                            .background(Color.matrixBackgroundSecondary)
                            .cornerRadius(.matrixCornerRadius)
                        }

                        // Create button
                        Button(action: createTask) {
                            HStack {
                                if isCreating {
                                    ProgressView()
                                        .tint(.matrixBackground)
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Create Task")
                                }
                            }
                            .font(.matrixHeadline)
                            .foregroundColor(.matrixBackground)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(title.isEmpty ? Color.matrixTextSecondary : Color.matrixNeon)
                            .cornerRadius(.matrixCornerRadius)
                            .neonGlow(color: title.isEmpty ? .clear : .matrixNeon)
                        }
                        .disabled(title.isEmpty || isCreating)
                    }
                    .padding()
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.matrixTextSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Actions

    private func createTask() {
        Task {
            isCreating = true
            defer { isCreating = false }

            do {
                try await viewModel.createTask(
                    title: title,
                    description: description,
                    priority: priority,
                    storyPoints: storyPoints,
                    frequencyDays: frequencyDays
                )
                dismiss()
            } catch {
                viewModel.errorMessage = "Failed to create task: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Priority Button

struct PriorityButton: View {
    let priority: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(priority)")
                    .font(.matrixBodyBold)

                Text(priorityLabel)
                    .font(.matrixCaption2)
            }
            .foregroundColor(isSelected ? .matrixBackground : Color.priorityColor(for: priority))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.priorityColor(for: priority) : Color.matrixBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.priorityColor(for: priority), lineWidth: isSelected ? 2 : 1)
            )
        }
    }

    private var priorityLabel: String {
        switch priority {
        case 1: return "Low"
        case 2: return "Med-L"
        case 3: return "Med"
        case 4: return "Med-H"
        case 5: return "High"
        default: return ""
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CreateTaskView_Previews: PreviewProvider {
    static var previews: some View {
        CreateTaskView(viewModel: AppViewModel())
    }
}
#endif
