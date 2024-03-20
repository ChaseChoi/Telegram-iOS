import Foundation
import UIKit
import Display
import AsyncDisplayKit
import ComponentFlow
import SwiftSignalKit
import ViewControllerComponent
import ComponentDisplayAdapters
import TelegramPresentationData
import AccountContext
import TelegramCore
import MultilineTextComponent
import SolidRoundedButtonComponent
import PresentationDataUtils
import Markdown
import UndoUI
import AnimatedAvatarSetNode
import AvatarNode

private final class SendInviteLinkScreenComponent: Component {
    typealias EnvironmentType = ViewControllerComponentContainer.Environment
    
    let context: AccountContext
    let link: String?
    let peers: [EnginePeer]
    let peerPresences: [EnginePeer.Id: EnginePeer.Presence]
    
    init(
        context: AccountContext,
        link: String?,
        peers: [EnginePeer],
        peerPresences: [EnginePeer.Id: EnginePeer.Presence]
    ) {
        self.context = context
        self.link = link
        self.peers = peers
        self.peerPresences = peerPresences
    }
    
    static func ==(lhs: SendInviteLinkScreenComponent, rhs: SendInviteLinkScreenComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.link != rhs.link {
            return false
        }
        if lhs.peers != rhs.peers {
            return false
        }
        if lhs.peerPresences != rhs.peerPresences {
            return false
        }
        return true
    }
    
    private struct ItemLayout: Equatable {
        var containerSize: CGSize
        var containerInset: CGFloat
        var bottomInset: CGFloat
        var topInset: CGFloat
        
        init(containerSize: CGSize, containerInset: CGFloat, bottomInset: CGFloat, topInset: CGFloat) {
            self.containerSize = containerSize
            self.containerInset = containerInset
            self.bottomInset = bottomInset
            self.topInset = topInset
        }
    }
    
    private final class ScrollView: UIScrollView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            return super.hitTest(point, with: event)
        }
    }
    
    final class View: UIView, UIScrollViewDelegate {
        private let dimView: UIView
        private let backgroundLayer: SimpleLayer
        private let navigationBarContainer: SparseContainerView
        private let scrollView: ScrollView
        private let scrollContentClippingView: SparseContainerView
        private let scrollContentView: UIView
        
        private var avatarsNode: AnimatedAvatarSetNode?
        private let avatarsContext = AnimatedAvatarSetContext()
        
        private var premiumTitle: ComponentView<Empty>?
        private var premiumText: ComponentView<Empty>?
        private var premiumButton: ComponentView<Empty>?
        private var premiumSeparatorLeft: SimpleLayer?
        private var premiumSeparatorRight: SimpleLayer?
        private var premiumSeparatorText: ComponentView<Empty>?
        
        private let leftButton = ComponentView<Empty>()
        
        private var title: ComponentView<Empty>?
        private var descriptionText: ComponentView<Empty>?
        private var actionButton: ComponentView<Empty>?
        
        private let itemContainerView: UIView
        private var items: [AnyHashable: ComponentView<Empty>] = [:]
        
        private var selectedItems = Set<EnginePeer.Id>()
        
        private let bottomOverscrollLimit: CGFloat
        
        private var ignoreScrolling: Bool = false
        
        private var component: SendInviteLinkScreenComponent?
        private weak var state: EmptyComponentState?
        private var environment: ViewControllerComponentContainer.Environment?
        private var itemLayout: ItemLayout?
        
        private var topOffsetDistance: CGFloat?
        
        override init(frame: CGRect) {
            self.bottomOverscrollLimit = 200.0
            
            self.dimView = UIView()
            
            self.backgroundLayer = SimpleLayer()
            self.backgroundLayer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            self.backgroundLayer.cornerRadius = 10.0
            
            self.navigationBarContainer = SparseContainerView()
            
            self.scrollView = ScrollView()
            
            self.scrollContentClippingView = SparseContainerView()
            self.scrollContentClippingView.clipsToBounds = true
            
            self.scrollContentView = UIView()
            
            self.itemContainerView = UIView()
            self.itemContainerView.clipsToBounds = true
            self.itemContainerView.layer.cornerRadius = 10.0
            
            super.init(frame: frame)
            
            self.addSubview(self.dimView)
            self.layer.addSublayer(self.backgroundLayer)
            
            self.addSubview(self.navigationBarContainer)
            
            self.scrollView.delaysContentTouches = true
            self.scrollView.canCancelContentTouches = true
            self.scrollView.clipsToBounds = false
            if #available(iOSApplicationExtension 11.0, iOS 11.0, *) {
                self.scrollView.contentInsetAdjustmentBehavior = .never
            }
            if #available(iOS 13.0, *) {
                self.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
            }
            self.scrollView.showsVerticalScrollIndicator = false
            self.scrollView.showsHorizontalScrollIndicator = false
            self.scrollView.alwaysBounceHorizontal = false
            self.scrollView.alwaysBounceVertical = true
            self.scrollView.scrollsToTop = false
            self.scrollView.delegate = self
            self.scrollView.clipsToBounds = true
            
            self.addSubview(self.scrollContentClippingView)
            self.scrollContentClippingView.addSubview(self.scrollView)
            
            self.scrollView.addSubview(self.scrollContentView)
            
            self.scrollContentView.addSubview(self.itemContainerView)
            
            self.dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dimTapGesture(_:))))
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if !self.ignoreScrolling {
                self.updateScrolling(transition: .immediate)
            }
        }
        
        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            guard let itemLayout = self.itemLayout, let topOffsetDistance = self.topOffsetDistance else {
                return
            }
            
            var topOffset = -self.scrollView.bounds.minY + itemLayout.topInset
            topOffset = max(0.0, topOffset)
            
            if topOffset < topOffsetDistance {
                targetContentOffset.pointee.y = scrollView.contentOffset.y
                scrollView.setContentOffset(CGPoint(x: 0.0, y: itemLayout.topInset), animated: true)
            }
        }
        
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            if !self.bounds.contains(point) {
                return nil
            }
            if !self.backgroundLayer.frame.contains(point) {
                return self.dimView
            }
            
            if let result = self.navigationBarContainer.hitTest(self.convert(point, to: self.navigationBarContainer), with: event) {
                return result
            }
            
            let result = super.hitTest(point, with: event)
            return result
        }
        
        @objc private func dimTapGesture(_ recognizer: UITapGestureRecognizer) {
            if case .ended = recognizer.state {
                guard let environment = self.environment, let controller = environment.controller() else {
                    return
                }
                controller.dismiss()
            }
        }
        
        private func updateScrolling(transition: Transition) {
            guard let environment = self.environment, let controller = environment.controller(), let itemLayout = self.itemLayout else {
                return
            }
            var topOffset = -self.scrollView.bounds.minY + itemLayout.topInset
            topOffset = max(0.0, topOffset)
            transition.setTransform(layer: self.backgroundLayer, transform: CATransform3DMakeTranslation(0.0, topOffset + itemLayout.containerInset, 0.0))
            
            transition.setPosition(view: self.navigationBarContainer, position: CGPoint(x: 0.0, y: topOffset + itemLayout.containerInset))
            
            let topOffsetDistance: CGFloat = min(200.0, floor(itemLayout.containerSize.height * 0.25))
            self.topOffsetDistance = topOffsetDistance
            var topOffsetFraction = topOffset / topOffsetDistance
            topOffsetFraction = max(0.0, min(1.0, topOffsetFraction))
            
            let transitionFactor: CGFloat = 1.0 - topOffsetFraction
            controller.updateModalStyleOverlayTransitionFactor(transitionFactor, transition: transition.containedViewLayoutTransition)
        }
        
        func animateIn() {
            self.dimView.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
            let animateOffset: CGFloat = self.bounds.height - self.backgroundLayer.frame.minY
            self.scrollContentClippingView.layer.animatePosition(from: CGPoint(x: 0.0, y: animateOffset), to: CGPoint(), duration: 0.5, timingFunction: kCAMediaTimingFunctionSpring, additive: true)
            self.backgroundLayer.animatePosition(from: CGPoint(x: 0.0, y: animateOffset), to: CGPoint(), duration: 0.5, timingFunction: kCAMediaTimingFunctionSpring, additive: true)
            self.navigationBarContainer.layer.animatePosition(from: CGPoint(x: 0.0, y: animateOffset), to: CGPoint(), duration: 0.5, timingFunction: kCAMediaTimingFunctionSpring, additive: true)
            if let actionButtonView = self.actionButton?.view {
                actionButtonView.layer.animatePosition(from: CGPoint(x: 0.0, y: animateOffset), to: CGPoint(), duration: 0.5, timingFunction: kCAMediaTimingFunctionSpring, additive: true)
            }
        }
        
        func animateOut(completion: @escaping () -> Void) {
            let animateOffset: CGFloat = self.bounds.height - self.backgroundLayer.frame.minY
            
            self.dimView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false)
            self.scrollContentClippingView.layer.animatePosition(from: CGPoint(), to: CGPoint(x: 0.0, y: animateOffset), duration: 0.3, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: false, additive: true, completion: { _ in
                completion()
            })
            self.backgroundLayer.animatePosition(from: CGPoint(), to: CGPoint(x: 0.0, y: animateOffset), duration: 0.3, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: false, additive: true)
            self.navigationBarContainer.layer.animatePosition(from: CGPoint(), to: CGPoint(x: 0.0, y: animateOffset), duration: 0.3, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: false, additive: true)
            if let actionButtonView = self.actionButton?.view {
                actionButtonView.layer.animatePosition(from: CGPoint(), to: CGPoint(x: 0.0, y: animateOffset), duration: 0.3, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: false, additive: true)
            }
        }
        
        func update(component: SendInviteLinkScreenComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<ViewControllerComponentContainer.Environment>, transition: Transition) -> CGSize {
            let environment = environment[ViewControllerComponentContainer.Environment.self].value
            let themeUpdated = self.environment?.theme !== environment.theme
            
            let resetScrolling = self.scrollView.bounds.width != availableSize.width
            
            let sideInset: CGFloat = 16.0
            
            if self.component == nil {
                for peer in component.peers {
                    self.selectedItems.insert(peer.id)
                }
            }
            
            self.component = component
            self.state = state
            self.environment = environment
            
            let hasPremiumRestrictedUsers = "".isEmpty
            let hasInviteLink = "".isEmpty
            
            if themeUpdated {
                self.dimView.backgroundColor = UIColor(white: 0.0, alpha: 0.5)
                self.backgroundLayer.backgroundColor = environment.theme.list.blocksBackgroundColor.cgColor
                self.itemContainerView.backgroundColor = environment.theme.list.itemBlocksBackgroundColor
                
                var locations: [NSNumber] = []
                var colors: [CGColor] = []
                let numStops = 6
                for i in 0 ..< numStops {
                    let step = CGFloat(i) / CGFloat(numStops - 1)
                    locations.append(step as NSNumber)
                    colors.append(environment.theme.list.blocksBackgroundColor.withAlphaComponent(1.0 - step * step).cgColor)
                }
            }
            
            transition.setFrame(view: self.dimView, frame: CGRect(origin: CGPoint(), size: availableSize))
            
            var contentHeight: CGFloat = 0.0
            contentHeight += 102.0
            
            let avatarsNode: AnimatedAvatarSetNode
            if let current = self.avatarsNode {
                avatarsNode = current
            } else {
                avatarsNode = AnimatedAvatarSetNode()
                self.avatarsNode = avatarsNode
                self.scrollContentView.addSubview(avatarsNode.view)
            }
            
            let avatarsContent = self.avatarsContext.update(peers: component.peers.count <= 3 ? component.peers : Array(component.peers.prefix(upTo: 3)), animated: false)
            let avatarsSize = avatarsNode.update(
                context: component.context,
                content: avatarsContent,
                itemSize: CGSize(width: 60.0, height: 60.0),
                customSpacing: 50.0,
                font: avatarPlaceholderFont(size: 28.0),
                animated: false,
                synchronousLoad: true
            )
            let avatarsFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - avatarsSize.width) * 0.5), y: 26.0), size: avatarsSize)
            transition.setFrame(view: avatarsNode.view, frame: avatarsFrame)
            
            let leftButtonSize = self.leftButton.update(
                transition: transition,
                component: AnyComponent(Button(
                    content: AnyComponent(Text(text: environment.strings.Common_Cancel, font: Font.regular(17.0), color: environment.theme.list.itemAccentColor)),
                    action: { [weak self] in
                        guard let self, let controller = self.environment?.controller() else {
                            return
                        }
                        controller.dismiss()
                    }
                ).minSize(CGSize(width: 44.0, height: 56.0))),
                environment: {},
                containerSize: CGSize(width: 120.0, height: 100.0)
            )
            let leftButtonFrame = CGRect(origin: CGPoint(x: 16.0, y: 0.0), size: leftButtonSize)
            if let leftButtonView = self.leftButton.view {
                if leftButtonView.superview == nil {
                    self.navigationBarContainer.addSubview(leftButtonView)
                }
                transition.setFrame(view: leftButtonView, frame: leftButtonFrame)
            }
            
            if hasPremiumRestrictedUsers {
                var premiumItemsTransition = transition
                
                let premiumTitle: ComponentView<Empty>
                if let current = self.premiumTitle {
                    premiumTitle = current
                } else {
                    premiumTitle = ComponentView()
                    self.premiumTitle = premiumTitle
                    premiumItemsTransition = premiumItemsTransition.withAnimation(.none)
                }
                
                let premiumText: ComponentView<Empty>
                if let current = self.premiumText {
                    premiumText = current
                } else {
                    premiumText = ComponentView()
                    self.premiumText = premiumText
                }
                
                let premiumButton: ComponentView<Empty>
                if let current = self.premiumButton {
                    premiumButton = current
                } else {
                    premiumButton = ComponentView()
                    self.premiumButton = premiumButton
                }
                
                //TODO:localize
                let premiumTitleSize = premiumTitle.update(
                    transition: .immediate,
                    component: AnyComponent(MultilineTextComponent(
                        text: .plain(NSAttributedString(string: "Upgrade to Premium", font: Font.semibold(24.0), textColor: environment.theme.list.itemPrimaryTextColor))
                    )),
                    environment: {},
                    containerSize: CGSize(width: availableSize.width - leftButtonFrame.maxX * 2.0, height: 100.0)
                )
                let premiumTitleFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - premiumTitleSize.width) * 0.5), y: contentHeight), size: premiumTitleSize)
                if let premiumTitleView = premiumTitle.view {
                    if premiumTitleView.superview == nil {
                        self.scrollContentView.addSubview(premiumTitleView)
                    }
                    transition.setFrame(view: premiumTitleView, frame: premiumTitleFrame)
                }
                
                contentHeight += premiumTitleSize.height
                contentHeight += 8.0
                
                //TODO:localize
                let text: String
                if component.peers.count == 1 {
                    text = "**\(component.peers[0].compactDisplayTitle)** accepts invitations to groups from contacts and **Premium** users."
                } else {
                    let extraCount = component.peers.count - 3
                    
                    var peersText = ""
                    for i in 0 ..< min(3, component.peers.count) {
                        if extraCount == 0 && i == component.peers.count - 1 {
                            peersText.append(", and ")
                        } else if i != 0 {
                            peersText.append(", ")
                        }
                        peersText.append("**")
                        peersText.append(component.peers[i].compactDisplayTitle)
                        peersText.append("**")
                    }
                    
                    if extraCount >= 1 {
                        if extraCount == 1 {
                            text = "\(peersText), and **\(extraCount)** more person only accept invitations to groups from contacts and **Premium** users."
                        } else {
                            text = "\(peersText), and **\(extraCount)** more people only accept invitations to groups from contacts and **Premium** users."
                        }
                    } else {
                        text = "\(peersText) only accept invitations to groups from contacts and **Premium** users."
                    }
                }
                
                let body = MarkdownAttributeSet(font: Font.regular(15.0), textColor: environment.theme.list.itemPrimaryTextColor)
                let bold = MarkdownAttributeSet(font: Font.semibold(15.0), textColor: environment.theme.list.itemPrimaryTextColor)
                
                let premiumTextSize = premiumText.update(
                    transition: .immediate,
                    component: AnyComponent(MultilineTextComponent(
                        text: .markdown(text: text, attributes: MarkdownAttributes(
                            body: body,
                            bold: bold,
                            link: body,
                            linkAttribute: { _ in nil }
                        )),
                        horizontalAlignment: .center,
                        maximumNumberOfLines: 0
                    )),
                    environment: {},
                    containerSize: CGSize(width: availableSize.width - sideInset * 2.0 - 16.0 * 2.0, height: 1000.0)
                )
                let premiumTextFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - premiumTextSize.width) * 0.5), y: contentHeight), size: premiumTextSize)
                if let premiumTextView = premiumText.view {
                    if premiumTextView.superview == nil {
                        self.scrollContentView.addSubview(premiumTextView)
                    }
                    transition.setFrame(view: premiumTextView, frame: premiumTextFrame)
                }
                
                contentHeight += premiumTextSize.height
                contentHeight += 22.0
                
                let premiumButtonTitle = "Subscribe to Telegram Premium"
                let premiumButtonSize = premiumButton.update(
                    transition: transition,
                    component: AnyComponent(SolidRoundedButtonComponent(
                        title: premiumButtonTitle,
                        badge: nil,
                        theme: SolidRoundedButtonComponent.Theme(
                            backgroundColor: .black,
                            backgroundColors: [
                                UIColor(rgb: 0x0077ff),
                                UIColor(rgb: 0x6b93ff),
                                UIColor(rgb: 0x8878ff),
                                UIColor(rgb: 0xe46ace)
                            ],
                            foregroundColor: .white
                        ),
                        font: .bold,
                        fontSize: 17.0,
                        height: 50.0,
                        cornerRadius: 11.0,
                        gloss: false,
                        animationName: nil,
                        iconPosition: .right,
                        iconSpacing: 4.0,
                        action: { [weak self] in
                            guard let self, let component = self.component, let controller = self.environment?.controller() else {
                                return
                            }
                            
                            let navigationController = controller.navigationController as? NavigationController
                            
                            controller.dismiss()
                            
                            //TODO:localize
                            let premiumController = component.context.sharedContext.makePremiumIntroController(context: component.context, source: .settings, forceDark: false, dismissed: nil)
                            navigationController?.pushViewController(premiumController)
                        }
                    )),
                    environment: {},
                    containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: 50.0)
                )
                
                let premiumButtonFrame = CGRect(origin: CGPoint(x: sideInset, y: contentHeight), size: premiumButtonSize)
                if let premiumButtonView = premiumButton.view {
                    if premiumButtonView.superview == nil {
                        self.scrollContentView.addSubview(premiumButtonView)
                    }
                    transition.setFrame(view: premiumButtonView, frame: premiumButtonFrame)
                }
                contentHeight += premiumButtonSize.height
                
                if hasInviteLink {
                    let premiumSeparatorText: ComponentView<Empty>
                    if let current = self.premiumSeparatorText {
                        premiumSeparatorText = current
                    } else {
                        premiumSeparatorText = ComponentView()
                        self.premiumSeparatorText = premiumSeparatorText
                    }
                    
                    let premiumSeparatorLeft: SimpleLayer
                    if let current = self.premiumSeparatorLeft {
                        premiumSeparatorLeft = current
                    } else {
                        premiumSeparatorLeft = SimpleLayer()
                        self.premiumSeparatorLeft = premiumSeparatorLeft
                        self.scrollContentView.layer.addSublayer(premiumSeparatorLeft)
                    }
                    
                    let premiumSeparatorRight: SimpleLayer
                    if let current = self.premiumSeparatorRight {
                        premiumSeparatorRight = current
                    } else {
                        premiumSeparatorRight = SimpleLayer()
                        self.premiumSeparatorRight = premiumSeparatorRight
                        self.scrollContentView.layer.addSublayer(premiumSeparatorRight)
                    }
                    
                    premiumSeparatorLeft.backgroundColor = environment.theme.list.itemPlainSeparatorColor.cgColor
                    premiumSeparatorRight.backgroundColor = environment.theme.list.itemPlainSeparatorColor.cgColor
                    
                    contentHeight += 19.0
                    
                    let premiumSeparatorTextSize = premiumSeparatorText.update(
                        transition: .immediate,
                        component: AnyComponent(MultilineTextComponent(
                            text: .plain(NSAttributedString(string: "or", font: Font.regular(15.0), textColor: environment.theme.list.itemSecondaryTextColor))
                        )),
                        environment: {},
                        containerSize: CGSize(width: availableSize.width - leftButtonFrame.maxX * 2.0, height: 100.0)
                    )
                    let premiumSeparatorTextFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - premiumSeparatorTextSize.width) * 0.5), y: contentHeight), size: premiumSeparatorTextSize)
                    if let premiumSeparatorTextView = premiumSeparatorText.view {
                        if premiumSeparatorTextView.superview == nil {
                            self.scrollContentView.addSubview(premiumSeparatorTextView)
                        }
                        transition.setFrame(view: premiumSeparatorTextView, frame: premiumSeparatorTextFrame)
                    }
                    
                    let separatorWidth: CGFloat = 72.0
                    let separatorSpacing: CGFloat = 10.0
                    
                    transition.setFrame(layer: premiumSeparatorLeft, frame: CGRect(origin: CGPoint(x: premiumSeparatorTextFrame.minX - separatorSpacing - separatorWidth, y: premiumSeparatorTextFrame.midY + 1.0), size: CGSize(width: separatorWidth, height: UIScreenPixel)))
                    transition.setFrame(layer: premiumSeparatorRight, frame: CGRect(origin: CGPoint(x: premiumSeparatorTextFrame.maxX + separatorSpacing, y: premiumSeparatorTextFrame.midY + 1.0), size: CGSize(width: separatorWidth, height: UIScreenPixel)))
                    
                    contentHeight += 31.0
                } else {
                    if let premiumSeparatorLeft = self.premiumSeparatorLeft {
                        self.premiumSeparatorLeft = nil
                        premiumSeparatorLeft.removeFromSuperlayer()
                    }
                    if let premiumSeparatorRight = self.premiumSeparatorRight {
                        self.premiumSeparatorRight = nil
                        premiumSeparatorRight.removeFromSuperlayer()
                    }
                    if let premiumSeparatorText = self.premiumSeparatorText {
                        self.premiumSeparatorText = nil
                        premiumSeparatorText.view?.removeFromSuperview()
                    }
                    
                    contentHeight += 14.0
                }
            } else {
                if let premiumTitle = self.premiumTitle {
                    self.premiumTitle = nil
                    premiumTitle.view?.removeFromSuperview()
                }
                if let premiumText = self.premiumText {
                    self.premiumText = nil
                    premiumText.view?.removeFromSuperview()
                }
                if let premiumButton = self.premiumButton {
                    self.premiumButton = nil
                    premiumButton.view?.removeFromSuperview()
                }
            }
            
            let containerInset: CGFloat = environment.statusBarHeight + 10.0
            
            var initialContentHeight = contentHeight
            let clippingY: CGFloat
            
            if hasInviteLink {
                let title: ComponentView<Empty>
                if let current = self.title {
                    title = current
                } else {
                    title = ComponentView()
                    self.title = title
                }
                
                let descriptionText: ComponentView<Empty>
                if let current = self.descriptionText {
                    descriptionText = current
                } else {
                    descriptionText = ComponentView()
                    self.descriptionText = descriptionText
                }
                
                let actionButton: ComponentView<Empty>
                if let current = self.actionButton {
                    actionButton = current
                } else {
                    actionButton = ComponentView()
                    self.actionButton = actionButton
                }
                
                let titleSize = title.update(
                    transition: .immediate,
                    component: AnyComponent(MultilineTextComponent(
                        text: .plain(NSAttributedString(string: component.link != nil ? environment.strings.SendInviteLink_InviteTitle : environment.strings.SendInviteLink_LinkUnavailableTitle, font: Font.semibold(24.0), textColor: environment.theme.list.itemPrimaryTextColor))
                    )),
                    environment: {},
                    containerSize: CGSize(width: availableSize.width - leftButtonFrame.maxX * 2.0, height: 100.0)
                )
                let titleFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - titleSize.width) * 0.5), y: contentHeight), size: titleSize)
                if let titleView = title.view {
                    if titleView.superview == nil {
                        self.scrollContentView.addSubview(titleView)
                    }
                    transition.setFrame(view: titleView, frame: titleFrame)
                }
                
                contentHeight += titleSize.height
                contentHeight += 8.0
                
                let text: String
                if hasPremiumRestrictedUsers {
                    if component.link != nil {
                        //TODO:localize
                        text = "You can try to send an invite link instead."
                    } else {
                        if component.peers.count == 1 {
                            text = environment.strings.SendInviteLink_TextUnavailableSingleUser(component.peers[0].displayTitle(strings: environment.strings, displayOrder: .firstLast)).string
                        } else {
                            text = environment.strings.SendInviteLink_TextUnavailableMultipleUsers(Int32(component.peers.count))
                        }
                    }
                } else {
                    if component.link != nil {
                        if component.peers.count == 1 {
                            text = environment.strings.SendInviteLink_TextAvailableSingleUser(component.peers[0].displayTitle(strings: environment.strings, displayOrder: .firstLast)).string
                        } else {
                            text = environment.strings.SendInviteLink_TextAvailableMultipleUsers(Int32(component.peers.count))
                        }
                    } else {
                        if component.peers.count == 1 {
                            text = environment.strings.SendInviteLink_TextUnavailableSingleUser(component.peers[0].displayTitle(strings: environment.strings, displayOrder: .firstLast)).string
                        } else {
                            text = environment.strings.SendInviteLink_TextUnavailableMultipleUsers(Int32(component.peers.count))
                        }
                    }
                }
                
                let body = MarkdownAttributeSet(font: Font.regular(15.0), textColor: environment.theme.list.itemPrimaryTextColor)
                let bold = MarkdownAttributeSet(font: Font.semibold(15.0), textColor: environment.theme.list.itemPrimaryTextColor)
                
                let descriptionTextSize = descriptionText.update(
                    transition: .immediate,
                    component: AnyComponent(MultilineTextComponent(
                        text: .markdown(text: text, attributes: MarkdownAttributes(
                            body: body,
                            bold: bold,
                            link: body,
                            linkAttribute: { _ in nil }
                        )),
                        horizontalAlignment: .center,
                        maximumNumberOfLines: 0
                    )),
                    environment: {},
                    containerSize: CGSize(width: availableSize.width - sideInset * 2.0 - 16.0 * 2.0, height: 1000.0)
                )
                let descriptionTextFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - descriptionTextSize.width) * 0.5), y: contentHeight), size: descriptionTextSize)
                if let descriptionTextView = descriptionText.view {
                    if descriptionTextView.superview == nil {
                        self.scrollContentView.addSubview(descriptionTextView)
                    }
                    transition.setFrame(view: descriptionTextView, frame: descriptionTextFrame)
                }
                
                contentHeight += descriptionTextFrame.height
                contentHeight += 22.0
                
                var singleItemHeight: CGFloat = 0.0
                
                var itemsHeight: CGFloat = 0.0
                var validIds: [AnyHashable] = []
                for i in 0 ..< component.peers.count {
                    let peer = component.peers[i]
                    
                    for _ in 0 ..< 1 {
                        //let id: AnyHashable = AnyHashable("\(peer.id)_\(j)")
                        let id = AnyHashable(peer.id)
                        validIds.append(id)
                        
                        let item: ComponentView<Empty>
                        var itemTransition = transition
                        if let current = self.items[id] {
                            item = current
                        } else {
                            itemTransition = .immediate
                            item = ComponentView()
                            self.items[id] = item
                        }
                        
                        let itemSize = item.update(
                            transition: itemTransition,
                            component: AnyComponent(PeerListItemComponent(
                                context: component.context,
                                theme: environment.theme,
                                strings: environment.strings,
                                sideInset: 0.0,
                                title: peer.displayTitle(strings: environment.strings, displayOrder: .firstLast),
                                peer: peer,
                                presence: component.peerPresences[peer.id],
                                selectionState: component.link == nil ? .none : .editing(isSelected: self.selectedItems.contains(peer.id)),
                                hasNext: i != component.peers.count - 1,
                                action: { [weak self] peer in
                                    guard let self else {
                                        return
                                    }
                                    if self.selectedItems.contains(peer.id) {
                                        self.selectedItems.remove(peer.id)
                                    } else {
                                        self.selectedItems.insert(peer.id)
                                    }
                                    self.state?.updated(transition: Transition(animation: .curve(duration: 0.3, curve: .easeInOut)))
                                }
                            )),
                            environment: {},
                            containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: 1000.0)
                        )
                        let itemFrame = CGRect(origin: CGPoint(x: 0.0, y: itemsHeight), size: itemSize)
                        
                        if let itemView = item.view {
                            if itemView.superview == nil {
                                self.itemContainerView.addSubview(itemView)
                            }
                            itemTransition.setFrame(view: itemView, frame: itemFrame)
                        }
                        
                        itemsHeight += itemSize.height
                        singleItemHeight = itemSize.height
                    }
                }
                var removeIds: [AnyHashable] = []
                for (id, item) in self.items {
                    if !validIds.contains(id) {
                        removeIds.append(id)
                        item.view?.removeFromSuperview()
                    }
                }
                for id in removeIds {
                    self.items.removeValue(forKey: id)
                }
                transition.setFrame(view: self.itemContainerView, frame: CGRect(origin: CGPoint(x: sideInset, y: contentHeight), size: CGSize(width: availableSize.width - sideInset * 2.0, height: itemsHeight)))
                
                initialContentHeight += singleItemHeight + 16.0
                initialContentHeight += min(itemsHeight, floor(singleItemHeight * 2.5))
                
                contentHeight += itemsHeight
                contentHeight += 24.0
                initialContentHeight += 24.0
                
                let actionButtonTitle: String
                if component.link != nil {
                    actionButtonTitle = self.selectedItems.isEmpty ? environment.strings.SendInviteLink_ActionSkip : environment.strings.SendInviteLink_ActionInvite
                } else {
                    actionButtonTitle = environment.strings.SendInviteLink_ActionClose
                }
                let actionButtonSize = actionButton.update(
                    transition: transition,
                    component: AnyComponent(SolidRoundedButtonComponent(
                        title: actionButtonTitle,
                        badge: (self.selectedItems.isEmpty || component.link == nil) ? nil : "\(self.selectedItems.count)",
                        theme: SolidRoundedButtonComponent.Theme(theme: environment.theme),
                        font: .bold,
                        fontSize: 17.0,
                        height: 50.0,
                        cornerRadius: 11.0,
                        gloss: false,
                        animationName: nil,
                        iconPosition: .right,
                        iconSpacing: 4.0,
                        action: { [weak self] in
                            guard let self, let component = self.component, let controller = self.environment?.controller() else {
                                return
                            }
                            if self.selectedItems.isEmpty {
                                controller.dismiss()
                            } else if let link = component.link {
                                let selectedPeers = component.peers.filter { self.selectedItems.contains($0.id) }
                                
                                let _ = enqueueMessagesToMultiplePeers(account: component.context.account, peerIds: Array(self.selectedItems), threadIds: [:], messages: [.message(text: link, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])]).start()
                                let text: String
                                if selectedPeers.count == 1 {
                                    text = environment.strings.Conversation_ShareLinkTooltip_Chat_One(selectedPeers[0].displayTitle(strings: environment.strings, displayOrder: .firstLast).replacingOccurrences(of: "*", with: "")).string
                                } else if selectedPeers.count == 2 {
                                    text = environment.strings.Conversation_ShareLinkTooltip_TwoChats_One(selectedPeers[0].displayTitle(strings: environment.strings, displayOrder: .firstLast).replacingOccurrences(of: "*", with: ""), selectedPeers[1].displayTitle(strings: environment.strings, displayOrder: .firstLast).replacingOccurrences(of: "*", with: "")).string
                                } else {
                                    text = environment.strings.Conversation_ShareLinkTooltip_ManyChats_One(selectedPeers[0].displayTitle(strings: environment.strings, displayOrder: .firstLast).replacingOccurrences(of: "*", with: ""), "\(selectedPeers.count - 1)").string
                                }
                                
                                let presentationData = component.context.sharedContext.currentPresentationData.with { $0 }
                                controller.present(UndoOverlayController(presentationData: presentationData, content: .forward(savedMessages: false, text: text), elevatedLayout: false, action: { _ in return false }), in: .window(.root))
                                
                                controller.dismiss()
                            } else {
                                controller.dismiss()
                            }
                        }
                    )),
                    environment: {},
                    containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: 50.0)
                )
                let bottomPanelHeight = 15.0 + environment.safeInsets.bottom + actionButtonSize.height
                let actionButtonFrame = CGRect(origin: CGPoint(x: sideInset, y: availableSize.height - bottomPanelHeight), size: actionButtonSize)
                if let actionButtonView = actionButton.view {
                    if actionButtonView.superview == nil {
                        self.addSubview(actionButtonView)
                    }
                    transition.setFrame(view: actionButtonView, frame: actionButtonFrame)
                }
                
                contentHeight += bottomPanelHeight
                initialContentHeight += bottomPanelHeight
                
                clippingY = actionButtonFrame.minY - 24.0
            } else {
                if let title = self.title {
                    self.title = nil
                    title.view?.removeFromSuperview()
                }
                if let descriptionText = self.descriptionText {
                    self.descriptionText = nil
                    descriptionText.view?.removeFromSuperview()
                }
                if let actionButton = self.actionButton {
                    self.actionButton = nil
                    actionButton.view?.removeFromSuperview()
                }
                
                initialContentHeight += environment.safeInsets.bottom
                
                clippingY = availableSize.height
            }
            
            let topInset: CGFloat = max(0.0, availableSize.height - containerInset - initialContentHeight)
            
            let scrollContentHeight = max(topInset + contentHeight, availableSize.height - containerInset)
            
            self.scrollContentClippingView.layer.cornerRadius = 10.0
            
            self.itemLayout = ItemLayout(containerSize: availableSize, containerInset: containerInset, bottomInset: environment.safeInsets.bottom, topInset: topInset)
            
            transition.setFrame(view: self.scrollContentView, frame: CGRect(origin: CGPoint(x: 0.0, y: topInset + containerInset), size: CGSize(width: availableSize.width, height: contentHeight)))
            
            transition.setPosition(layer: self.backgroundLayer, position: CGPoint(x: availableSize.width / 2.0, y: availableSize.height / 2.0))
            transition.setBounds(layer: self.backgroundLayer, bounds: CGRect(origin: CGPoint(), size: availableSize))
            
            let scrollClippingFrame = CGRect(origin: CGPoint(x: sideInset, y: containerInset), size: CGSize(width: availableSize.width - sideInset * 2.0, height: clippingY - containerInset))
            transition.setPosition(view: self.scrollContentClippingView, position: scrollClippingFrame.center)
            transition.setBounds(view: self.scrollContentClippingView, bounds: CGRect(origin: CGPoint(x: scrollClippingFrame.minX, y: scrollClippingFrame.minY), size: scrollClippingFrame.size))
            
            self.ignoreScrolling = true
            transition.setFrame(view: self.scrollView, frame: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: availableSize.width, height: availableSize.height)))
            let contentSize = CGSize(width: availableSize.width, height: scrollContentHeight)
            if contentSize != self.scrollView.contentSize {
                self.scrollView.contentSize = contentSize
            }
            if resetScrolling {
                self.scrollView.bounds = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: availableSize)
            }
            self.ignoreScrolling = false
            self.updateScrolling(transition: transition)
            
            return availableSize
        }
    }
    
    func makeView() -> View {
        return View(frame: CGRect())
    }
    
    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<ViewControllerComponentContainer.Environment>, transition: Transition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

public class SendInviteLinkScreen: ViewControllerComponentContainer {
    private let context: AccountContext
    private let link: String?
    private let peers: [EnginePeer]
    
    private var isDismissed: Bool = false
    
    private var presenceDisposable: Disposable?
    
    public init(context: AccountContext, peer: EnginePeer, link: String?, peers: [EnginePeer]) {
        self.context = context
        
        var link = link
        if link == nil, let addressName = peer.addressName {
            link = "https://t.me/\(addressName)"
        }
        
        self.link = link
        self.peers = peers
        
        super.init(context: context, component: SendInviteLinkScreenComponent(context: context, link: link, peers: peers, peerPresences: [:]), navigationBarAppearance: .none)
        
        self.statusBar.statusBarStyle = .Ignore
        self.navigationPresentation = .flatModal
        self.blocksBackgroundWhenInOverlay = true
        
        self.presenceDisposable = (context.engine.data.subscribe(EngineDataMap(
            peers.map(\.id).map(TelegramEngine.EngineData.Item.Peer.Presence.init(id:))
        ))
        |> deliverOnMainQueue).start(next: { [weak self] presences in
            guard let self else {
                return
            }
            var parsedPresences: [EnginePeer.Id: EnginePeer.Presence] = [:]
            for (id, presence) in presences {
                if let presence {
                    parsedPresences[id] = presence
                }
            }
            self.updateComponent(component: AnyComponent(SendInviteLinkScreenComponent(context: context, link: link, peers: peers, peerPresences: parsedPresences)), transition: .immediate)
        })
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.presenceDisposable?.dispose()
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.view.disablesInteractiveModalDismiss = true
        
        if let componentView = self.node.hostView.componentView as? SendInviteLinkScreenComponent.View {
            componentView.animateIn()
        }
    }
    
    override public func dismiss(completion: (() -> Void)? = nil) {
        if !self.isDismissed {
            self.isDismissed = true
            
            if let componentView = self.node.hostView.componentView as? SendInviteLinkScreenComponent.View {
                componentView.animateOut(completion: { [weak self] in
                    completion?()
                    self?.dismiss(animated: false)
                })
            } else {
                self.dismiss(animated: false)
            }
        }
    }
}
