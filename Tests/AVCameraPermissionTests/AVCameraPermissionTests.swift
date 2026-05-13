import Testing
import Domain
@testable import AVCameraPermission

@Suite("AVCameraPermission")
struct AVCameraPermissionTests {
    // MARK: - authorized 経路

    @Test("status が authorized なら success を返し requestAccess も alert も呼ばない")
    func authorizedReturnsSuccessWithoutSideEffects() async {
        let provider = FakeCameraAuthorizationProvider(status: .authorized)
        let presenter = SpyCameraPermissionAlertPresenter()
        let sut = AVCameraPermission(provider: provider, alertPresenter: presenter)

        let result = await sut.ensureGranted()

        #expect(result.isSuccess)
        await #expect(provider.requestAccessCallCount == 0)
        await #expect(presenter.deniedAlertCount == 0)
        await #expect(presenter.restrictedAlertCount == 0)
    }

    // MARK: - notDetermined 経路

    @Test("status が notDetermined で requestAccess が許可されたら success、alert は出さない")
    func notDeterminedGrantedReturnsSuccess() async {
        let provider = FakeCameraAuthorizationProvider(
            status: .notDetermined,
            grantOnRequest: true,
            postRequestStatus: .authorized
        )
        let presenter = SpyCameraPermissionAlertPresenter()
        let sut = AVCameraPermission(provider: provider, alertPresenter: presenter)

        let result = await sut.ensureGranted()

        #expect(result.isSuccess)
        await #expect(provider.requestAccessCallCount == 1)
        await #expect(presenter.deniedAlertCount == 0)
        await #expect(presenter.restrictedAlertCount == 0)
    }

    @Test("status が notDetermined で requestAccess が拒否されたら .denied、alert は出さない")
    func notDeterminedDeniedReturnsFailure() async {
        let provider = FakeCameraAuthorizationProvider(
            status: .notDetermined,
            grantOnRequest: false,
            postRequestStatus: .denied
        )
        let presenter = SpyCameraPermissionAlertPresenter()
        let sut = AVCameraPermission(provider: provider, alertPresenter: presenter)

        let result = await sut.ensureGranted()

        #expect(result.failureError == .denied)
        await #expect(provider.requestAccessCallCount == 1)
        // 初回拒否は OS のダイアログで明示的に NO を選んだ直後なので、
        // 同じセッションで重ねて alert を出さない（ユーザー体験を煩雑にしない）。
        await #expect(presenter.deniedAlertCount == 0)
        await #expect(presenter.restrictedAlertCount == 0)
    }

    // MARK: - denied 経路

    @Test("status が denied なら .denied を返し denied-alert を 1 回出し requestAccess は呼ばない")
    func deniedReturnsFailureAndPresentsAlert() async {
        let provider = FakeCameraAuthorizationProvider(status: .denied)
        let presenter = SpyCameraPermissionAlertPresenter()
        let sut = AVCameraPermission(provider: provider, alertPresenter: presenter)

        let result = await sut.ensureGranted()

        #expect(result.failureError == .denied)
        // requestAccess は notDetermined のときだけ意味がある。
        // denied 状態で呼んでも OS は no-op で false を返すだけで誤解を招くので呼ばない。
        await #expect(provider.requestAccessCallCount == 0)
        await #expect(presenter.deniedAlertCount == 1)
        await #expect(presenter.restrictedAlertCount == 0)
    }

    // MARK: - restricted 経路

    @Test("status が restricted なら .restricted を返し restricted-alert を 1 回出し requestAccess は呼ばない")
    func restrictedReturnsFailureAndPresentsAlert() async {
        let provider = FakeCameraAuthorizationProvider(status: .restricted)
        let presenter = SpyCameraPermissionAlertPresenter()
        let sut = AVCameraPermission(provider: provider, alertPresenter: presenter)

        let result = await sut.ensureGranted()

        #expect(result.failureError == .restricted)
        await #expect(provider.requestAccessCallCount == 0)
        await #expect(presenter.deniedAlertCount == 0)
        await #expect(presenter.restrictedAlertCount == 1)
    }

    // MARK: - 冪等性

    @Test("ensureGranted を 2 回呼んでも認可成功なら 2 回とも success（副作用は最小）")
    func authorizedIsIdempotent() async {
        let provider = FakeCameraAuthorizationProvider(status: .authorized)
        let presenter = SpyCameraPermissionAlertPresenter()
        let sut = AVCameraPermission(provider: provider, alertPresenter: presenter)

        let result1 = await sut.ensureGranted()
        let result2 = await sut.ensureGranted()

        #expect(result1.isSuccess)
        #expect(result2.isSuccess)
        await #expect(provider.requestAccessCallCount == 0)
    }

    // MARK: - AlwaysGrantedCameraPermission stub

    @Test("AlwaysGrantedCameraPermission は常に success を返す（DI testValue 用のスタブ）")
    func alwaysGrantedStubAlwaysSucceeds() async {
        let sut = AlwaysGrantedCameraPermission()
        let result = await sut.ensureGranted()
        #expect(result.isSuccess)
    }
}

private extension Result where Success == Void {
    /// `Result<Void, Failure>` は `Void` が Equatable でないため `==` で
    /// 比較できない。テスト内でだけ使う syntactic sugar。
    var isSuccess: Bool {
        switch self {
        case .success: return true
        case .failure: return false
        }
    }

    /// `failure` ケースから具体的なエラーを取り出す。`.success` の場合は `nil`。
    var failureError: Failure? {
        switch self {
        case .success: return nil
        case .failure(let error): return error
        }
    }
}
