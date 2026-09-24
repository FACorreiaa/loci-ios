import Connect
import Foundation
import LociConnectProto
import Testing

@testable import loci

struct AppendTranscriptTests {
  @Test("empty field takes the transcript as-is, trimmed")
  func emptyField() {
    #expect(appendTranscript("", "  3 days in Lisbon ") == "3 days in Lisbon")
  }

  @Test("typed text and transcript join with one space")
  func joinsWithOneSpace() {
    #expect(appendTranscript("Porto", "with kids") == "Porto with kids")
    #expect(appendTranscript("Porto ", " with kids") == "Porto with kids")
    #expect(appendTranscript("  Porto\n", "with kids") == "Porto with kids")
  }

  @Test("an empty transcript leaves the text alone")
  func emptyTranscript() {
    #expect(appendTranscript("Porto", "   ") == "Porto")
    #expect(appendTranscript("", "").isEmpty)
  }
}

struct DictationErrorTests {
  @Test(
    "Connect codes map to what the composer does",
    arguments: [
      (Code.failedPrecondition, DictationError.unavailable),
      (.unavailable, .busy),
      (.invalidArgument, .rejected),
      (.resourceExhausted, .busy),
      (.internalError, .failed),
      (.unknown, .failed),
      (.unauthenticated, .failed),
    ]
  )
  func mapping(code: Code, expected: DictationError) {
    #expect(DictationError.from(code: code) == expected)
  }

  @Test("every failure has a short message")
  func messages() {
    let all: [DictationError] = [.permissionDenied, .micFailed, .unavailable, .rejected, .busy, .failed, .nothingHeard]
    for error in all {
      #expect(!error.message.isEmpty)
      #expect(error.message.count < 100)
    }
    #expect(DictationError.nothingHeard.message == "I couldn't hear anything in that.")
  }

  @Test("an empty transcript is 'nothing heard', not a server error")
  func emptyTranscript() {
    #expect(throws: DictationError.nothingHeard) { try DictationError.transcript("") }
    #expect(throws: DictationError.nothingHeard) { try DictationError.transcript(" \n ") }
    #expect((try? DictationError.transcript(" Lisbon ")) == "Lisbon")
  }
}

@MainActor
struct DictationControllerTests {
  private static func reply(_ text: String) -> DictationController.Transcribe {
    { _ in
      var response = Loci_Speech_TranscribeResponse()
      response.text = text
      return ResponseMessage(result: .success(response))
    }
  }

  private static func failure(_ code: Code) -> DictationController.Transcribe {
    { _ in
      ResponseMessage(code: code, result: .failure(ConnectError(code: code, message: nil, exception: nil, details: [], metadata: [:])))
    }
  }

  @Test("upload returns the trimmed transcript")
  func transcript() async throws {
    let controller = DictationController(transcribe: Self.reply(" two days in Rome "))
    #expect(try await controller.transcribe(Data([1])) == "two days in Rome")
  }

  @Test("upload with an empty transcript throws nothingHeard")
  func emptyTranscript() async {
    let controller = DictationController(transcribe: Self.reply(""))
    await #expect(throws: DictationError.nothingHeard) { try await controller.transcribe(Data([1])) }
  }

  @Test("upload maps the server's code")
  func serverCode() async {
    let controller = DictationController(transcribe: Self.failure(.failedPrecondition))
    await #expect(throws: DictationError.unavailable) { try await controller.transcribe(Data([1])) }
    let busy = DictationController(transcribe: Self.failure(.resourceExhausted))
    await #expect(throws: DictationError.busy) { try await busy.transcribe(Data([1])) }
    let transient = DictationController(transcribe: Self.failure(.unavailable))
    await #expect(throws: DictationError.busy) { try await transient.transcribe(Data([1])) }
  }
}
