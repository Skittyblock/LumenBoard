import Darwin
import UIKit

// Sheet shown while SpringBoard pre-renders the theme icons and resprings.
final class LMApplyViewController: UIViewController {
    private var clearIconCache: Bool
    private var springBoardAnswered = false
    private var progressToken: Int32 = NOTIFY_TOKEN_INVALID
    private var symbol: UIImageView!
    private var titleLabel: UILabel!
    private var statusLabel: UILabel!
    private var progressView: UIProgressView!
    private var closeButton: UIButton!

    @objc(initWithClearingIconCache:)
    init?(clearingIconCache clearIconCache: Bool) {
        self.clearIconCache = clearIconCache
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        isModalInPresentation = true
        let sheet = sheetPresentationController
        sheet?.detents = [.medium()]
        sheet?.preferredCornerRadius = 28
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if progressToken != NOTIFY_TOKEN_INVALID {
            notify_cancel(progressToken)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        symbol = UIImageView(image: UIImage(systemName: "arrow.triangle.2.circlepath", withConfiguration: UIImage.SymbolConfiguration(pointSize: 52, weight: .medium)))
        symbol.tintColor = view.tintColor

        titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.text = clearIconCache ? LMLocalized("Rebuilding icons") : LMLocalized("Applying theme")

        progressView = UIProgressView(progressViewStyle: .default)
        progressView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel = UILabel()
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = LMLocalized("Preparing…")

        var configuration = UIButton.Configuration.gray()
        configuration.title = LMLocalized("Close")
        configuration.cornerStyle = .capsule
        closeButton = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true, completion: nil)
        })
        closeButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [symbol, titleLabel, progressView, statusLabel, closeButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.setCustomSpacing(24, after: symbol)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),
            progressView.widthAnchor.constraint(equalToConstant: 260),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard progressToken == NOTIFY_TOKEN_INVALID else { return }

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.toValue = Double.pi * 2
        spin.duration = 3
        spin.repeatCount = .infinity
        symbol.layer.add(spin, forKey: "spin")

        // SpringBoard reports (done << 32) | total while it renders the theme icons, done == UINT32_MAX before respringing
        notify_register_dispatch(LMNotifyProgress, &progressToken, .main) { [weak self] token in
            var state: UInt64 = 0
            notify_get_state(token, &state)
            self?.showProgress(UInt32(state >> 32), of: UInt32(state & 0xFFFFFFFF))
        }
        notify_post(clearIconCache ? LMNotifyClearCache : LMNotifyApply)
        Task { [weak self] in
            await LMConfigStore.shared.markApplied()

            try? await Task.sleep(nanoseconds: 30_000_000_000)

            self?.showFailureIfSpringBoardIsSilent()
        }
    }

    @objc func showProgress(_ done: UInt32, of total: UInt32) {
        springBoardAnswered = true
        if done == UInt32.max || total == 0 {
            progressView.progress = 1
            statusLabel.text = LMLocalized("Respringing…")
            return
        }
        progressView.setProgress(Float(done) / Float(total), animated: true)
        statusLabel.text = String.localizedStringWithFormat(LMLocalized("Rendering icons: %u of %u"), done, total)
    }

    @objc func showFailureIfSpringBoardIsSilent() {
        guard !springBoardAnswered else { return }
        symbol.layer.removeAllAnimations()
        symbol.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 52, weight: .medium))
        symbol.tintColor = .systemOrange
        progressView.isHidden = true
        statusLabel.text = LMLocalized("SpringBoard didn't answer. Make sure LumenBoard is enabled in your tweak injector, respring once and try again.")
        closeButton.isHidden = false
        isModalInPresentation = false
    }
}
