import SwiftUI

/// Write or edit a review (web: ReviewForm, without photos or travel type:
/// there is no upload RPC and no such field). Rating and 10–1000 characters are
/// required; the title is optional up to 100; the visit date is optional.
struct ReviewComposer: View {
  let placeName: String
  let onSubmit: (ReviewForm, LociReview?) async -> ReviewSubmitResult
  var onDelete: ((LociReview) async -> Bool)?
  /// The owner's error, shown over the sheet while it is open.
  @Binding var error: String?

  @Environment(\.dismiss) private var dismiss
  @State private var form: ReviewForm
  @State private var editing: LociReview?
  @State private var hasVisitDate: Bool
  @State private var saving = false
  @State private var confirmingDelete = false
  /// Set when a new review turned out to be a second one for this place.
  @State private var notice: String?

  init(
    mode: ReviewComposerMode,
    placeName: String,
    onSubmit: @escaping (ReviewForm, LociReview?) async -> ReviewSubmitResult,
    onDelete: ((LociReview) async -> Bool)? = nil,
    error: Binding<String?> = .constant(nil)
  ) {
    self.placeName = placeName
    self.onSubmit = onSubmit
    self.onDelete = onDelete
    _error = error
    let form = mode.review.map(ReviewForm.init) ?? ReviewForm()
    _form = State(initialValue: form)
    _editing = State(initialValue: mode.review)
    _hasVisitDate = State(initialValue: form.visitDate != nil)
  }

  private var isEditing: Bool { editing != nil }
  private var isDirty: Bool { form != (editing.map(ReviewForm.init) ?? ReviewForm()) }

  var body: some View {
    NavigationStack {
      Form {
        if let notice {
          Section { Label(notice, systemImage: "info.circle").font(.lociCaption(14)).foregroundStyle(Color.lociInk) }
        }
        Section {
          StarPicker(rating: $form.rating)
        } header: {
          Text(placeName.isEmpty ? "Your rating" : placeName)
        }
        titleSection
        contentSection
        Section {
          Toggle("I remember when I went", isOn: $hasVisitDate.animation())
          if hasVisitDate {
            DatePicker("Visited", selection: visitDate, in: ...Date(), displayedComponents: .date)
          }
        } footer: {
          Text("Optional. Only the month and year are shown.")
        }
        if let editing, onDelete != nil {
          Section {
            Button("Delete review", systemImage: "trash", role: .destructive) { confirmingDelete = true }
          }
          .confirmationDialog("Delete your review?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete(editing) } }
          } message: {
            Text("This can't be undone.")
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(Color.lociPaper.ignoresSafeArea())
      .navigationTitle(isEditing ? "Edit your review" : "Write a review")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          if saving {
            ProgressView()
          } else {
            Button(isEditing ? "Save" : "Post") { Task { await submit() } }.disabled(!form.isValid)
          }
        }
      }
    }
    .errorAlert($error)
    .interactiveDismissDisabled(saving || isDirty)
    .onAppear { Analytics.screen("review_composer", ["is_edit": isEditing]) }
  }

  private var titleSection: some View {
    Section {
      TextField("Sum it up in a line", text: $form.title)
        .onChange(of: form.title) { _, value in
          let clamped = ReviewForm.clampTitle(value)
          if clamped != value { form.title = clamped }
        }
    } header: {
      Text("Title (optional)")
    } footer: {
      counter(form.titleCounter, warning: form.title.count >= ReviewForm.titleLimit)
    }
  }

  private var contentSection: some View {
    Section {
      TextField("What was it like? What should the next person know?", text: $form.content, axis: .vertical)
        .lineLimit(5...12)
        .onChange(of: form.content) { _, value in
          let clamped = ReviewForm.clampContent(value)
          if clamped != value { form.content = clamped }
        }
    } header: {
      Text("Your review")
    } footer: {
      HStack {
        if form.issues.contains(.contentTooShort) {
          Text("At least \(ReviewForm.contentMinimum) characters").foregroundStyle(Color.lociCoral)
        }
        Spacer()
        counter(form.contentCounter, warning: form.trimmedContent.count >= ReviewForm.contentLimit)
      }
    }
  }

  private var visitDate: Binding<Date> {
    Binding(get: { form.visitDate ?? Date() }, set: { form.visitDate = $0 })
  }

  private func counter(_ text: String, warning: Bool) -> some View {
    Text(text).monospacedDigit().foregroundStyle(warning ? Color.lociCoral : Color.lociMutedInk)
  }

  private func submit() async {
    var outgoing = form
    if hasVisitDate {
      if outgoing.visitDate == nil { outgoing.visitDate = Date() }
    } else {
      outgoing.visitDate = nil
    }
    saving = true
    let result = await onSubmit(outgoing, editing)
    saving = false
    switch result {
    case .saved: dismiss()
    case .switchedToEdit(let existing):
      editing = existing
      notice = "You've already reviewed this place. Saving will update that review with what you wrote here."
    case .failed: break
    }
  }

  private func delete(_ review: LociReview) async {
    guard let onDelete else { return }
    saving = true
    let done = await onDelete(review)
    saving = false
    if done { dismiss() }
  }
}

/// Tap a star to rate; the label under it is web's word for that rating.
struct StarPicker: View {
  @Binding var rating: Int

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 10) {
        ForEach(ReviewRating.range, id: \.self) { star in
          Button {
            rating = star
          } label: {
            Image(systemName: star <= rating ? "star.fill" : "star")
              .font(.system(size: 30, weight: .medium))
              .foregroundStyle(star <= rating ? Color.lociCoral : Color.lociBorder)
              .symbolEffect(.bounce, value: rating == star)
              .frame(minWidth: 44, minHeight: 44)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("\(star) star\(star == 1 ? "" : "s"), \(ReviewRating.label(star))")
          .accessibilityAddTraits(star == rating ? .isSelected : [])
        }
      }
      Text(rating == 0 ? "Tap to rate" : ReviewRating.label(rating))
        .font(.lociHeadline(15))
        .foregroundStyle(rating == 0 ? Color.lociMutedInk : Color.lociInk)
        .contentTransition(.opacity)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 4)
  }
}
