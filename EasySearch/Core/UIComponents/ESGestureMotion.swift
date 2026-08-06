import CoreGraphics
import Foundation
import QuartzCore

/// 手势驱动动效的物理内核。
///
/// 设计目标(Designing Fluid Interfaces):
/// - 动画永远从当前呈现值出发,而不是从逻辑目标值出发,所以任何时刻都能被抓住;
/// - 释放时继承手势速度,而不是丢弃它;
/// - 打断并反向时速度是连续的,不出现"撞墙"感。
///
/// 用解析解逐帧求值,不依赖 SwiftUI 的 `withAnimation`,因此可以在动画进行中
/// 直接读到当前值与当前速度并无缝接管。
struct ESSpring {
    /// 视觉稳定时间(秒),对应 Apple 的 `duration`。
    var response: Double
    /// 0 = 临界阻尼(无回弹);0.15 左右是克制的回弹。
    var bounce: Double

    static let snap = ESSpring(response: 0.38, bounce: 0)
    static let gentle = ESSpring(response: 0.45, bounce: 0.12)

    var stiffness: Double {
        let omega = 2 * Double.pi / response
        return omega * omega
    }

    var dampingRatio: Double {
        bounce >= 0 ? 1 - bounce : 1 / (1 + bounce)
    }

    var damping: Double {
        2 * dampingRatio * (2 * Double.pi / response)
    }
}

/// 单轴弹簧求值器:持有位置与速度,可随时被重新指定目标而不丢速度。
struct ESSpringValue {
    private(set) var value: Double
    private(set) var velocity: Double
    var target: Double
    var spring: ESSpring

    init(value: Double, velocity: Double = 0, target: Double, spring: ESSpring = .snap) {
        self.value = value
        self.velocity = velocity
        self.target = target
        self.spring = spring
    }

    var isSettled: Bool {
        abs(value - target) < 0.5 && abs(velocity) < 8
    }

    /// 手势期间直接接管数值,并记录手势速度,供释放时继承。
    mutating func track(value newValue: Double, velocity newVelocity: Double) {
        value = newValue
        velocity = newVelocity
    }

    /// 重新指定目标。速度保持不变 —— 这正是反向时不"撞墙"的关键。
    mutating func retarget(_ newTarget: Double, spring newSpring: ESSpring? = nil) {
        target = newTarget
        if let newSpring {
            spring = newSpring
        }
    }

    /// 推进一帧。半隐式欧拉在 120Hz 下足够稳定,且天然支持中途改目标。
    mutating func advance(by deltaTime: Double) {
        let clampedStep = min(max(deltaTime, 1.0 / 240.0), 1.0 / 30.0)
        let displacement = value - target
        let acceleration = -spring.stiffness * displacement - spring.damping * velocity
        velocity += acceleration * clampedStep
        value += velocity * clampedStep

        // 临界阻尼（bounce = 0）理论上不应过冲；数值积分仍可能越过目标再抽回。
        if spring.bounce <= 0 {
            let crossed = (displacement > 0 && value < target) || (displacement < 0 && value > target)
            if crossed {
                value = target
                velocity = 0
            }
        }

        if isSettled {
            value = target
            velocity = 0
        }
    }
}

/// 把手势释放速度投射成落点,用来判断"轻扫是否算数",而不是只看位移。
enum ESGestureProjection {
    /// UIScrollView 同款减速常数。
    static let decelerationRate: Double = 0.998

    static func projectedOffset(velocity: Double) -> Double {
        let rate = decelerationRate
        return (velocity / 1000) * rate / (1 - rate)
    }

    /// 橡皮筋阻尼:越拉越沉,永不硬停。
    static func rubberBand(_ distance: Double, limit: Double, coefficient: Double = 0.55) -> Double {
        guard limit > 0 else { return 0 }
        let sign: Double = distance < 0 ? -1 : 1
        let magnitude = abs(distance)
        return sign * (1 - (1 / (magnitude * coefficient / limit + 1))) * limit
    }
}

/// 逐帧驱动器。用 `CADisplayLink` 保证与屏幕刷新率对齐(含 ProMotion 120Hz)。
@MainActor
final class ESDisplayLinkDriver {
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var onFrame: ((Double) -> Bool)?

    /// `frame` 返回 false 表示动画已结束,驱动器自动停止。
    func start(_ frame: @escaping (Double) -> Bool) {
        stop()
        onFrame = frame
        lastTimestamp = 0

        let link = CADisplayLink(target: ESDisplayLinkProxy { [weak self] link in
            self?.step(link)
        }, selector: #selector(ESDisplayLinkProxy.handle(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        onFrame = nil
        lastTimestamp = 0
    }

    var isRunning: Bool { displayLink != nil }

    private func step(_ link: CADisplayLink) {
        guard let onFrame else { return }

        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }

        let deltaTime = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp

        if !onFrame(deltaTime) {
            stop()
        }
    }
}

/// `CADisplayLink` 需要 NSObject target,这里用一个轻代理避免驱动器本身继承 NSObject。
private final class ESDisplayLinkProxy: NSObject {
    private let handler: (CADisplayLink) -> Void

    init(handler: @escaping (CADisplayLink) -> Void) {
        self.handler = handler
    }

    @objc func handle(_ link: CADisplayLink) {
        handler(link)
    }
}

/// 可打断的单轴滑动呈现器。
///
/// 与 `withAnimation` + `asyncAfter` 的关键区别:落位动画进行中,
/// 手指可以随时重新按下并从当前位置接管,已排队的"提交索引"不会先跑完再响应。
@MainActor
final class ESSlideAnimator: ObservableObject {
    @Published private(set) var translation: CGSize = .zero

    private let driver = ESDisplayLinkDriver()
    private var axis: ESSpringValue?
    private var isVerticalAxis = false
    private var pendingCommit: (() -> Void)?

    var isAnimating: Bool { driver.isRunning }

    /// 手势按下:停下正在跑的落位动画,把当前呈现值交还给手指。
    /// 返回当前偏移,调用方用它作为本次拖拽的基准点。
    @discardableResult
    func takeOver() -> CGSize {
        driver.stop()
        axis = nil
        pendingCommit = nil
        return translation
    }

    /// 手势期间 1:1 跟手。
    func track(_ newTranslation: CGSize) {
        translation = newTranslation
    }

    func reset() {
        driver.stop()
        axis = nil
        pendingCommit = nil
        translation = .zero
    }

    /// 释放后落位。`velocity` 为手势释放速度(pt/s),会被弹簧继承。
    func settle(
        to target: CGSize,
        vertical: Bool,
        velocity: CGFloat,
        spring: ESSpring,
        onCommit: (() -> Void)? = nil
    ) {
        isVerticalAxis = vertical
        pendingCommit = onCommit

        let current = vertical ? translation.height : translation.width
        let goal = vertical ? target.height : target.width

        axis = ESSpringValue(
            value: Double(current),
            velocity: Double(velocity),
            target: Double(goal),
            spring: spring
        )

        driver.start { [weak self] deltaTime in
            guard let self, var axis = self.axis else { return false }

            axis.advance(by: deltaTime)
            self.axis = axis
            self.translation = self.isVerticalAxis
                ? CGSize(width: 0, height: CGFloat(axis.value))
                : CGSize(width: CGFloat(axis.value), height: 0)

            guard axis.isSettled else { return true }

            let commit = self.pendingCommit
            self.pendingCommit = nil
            self.axis = nil
            commit?()
            return false
        }
    }
}
