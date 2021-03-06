/**
 *  BulletinBoard
 *  Copyright (c) 2017 Alexis Aubry. Licensed under the MIT license.
 */

import UIKit

/**
 * An object that manages the presentation of a bulletin.
 *
 * You create a bulletin manager using the `init(rootItem:)` initializer, where `rootItem` is the
 * first bulletin item to display.
 *
 * The manager works like a navigation controller. You can push new items to the stack to display them,
 * and pop existing ones to go back.
 *
 * You must call the `prepare` method before displaying the view controller.
 *
 * `BulletinManager` must only be used from the main thread.
 */

@objc public final class BulletinManager: NSObject {

    fileprivate var viewController: BulletinViewController!

    // MARK: - Configuration

    /**
     * The style of the view covering the content. Defaults to `.dimmed`.
     *
     * Set this value before calling `prepare`. Changing it after will have no effect.
     */

    @objc public var backgroundViewStyle: BulletinBackgroundViewStyle = .dimmed

    /**
     * The style of status bar to use with the bulltin. Defaults to `.automatic`.
     *
     * Set this value before calling `prepare`. Changing it after will have no effect.
     */

    @objc public var statusBarAppearance: BulletinStatusBarAppearance = .automatic

    /**
     * The background color to use with the bulletin. Defaults to `.white`
     *
     * Set this value before calling `prepare`. Changing it after will have no effect.
     */
    @objc public var backgroundColor: UIColor = #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)

    // MARK: - Private Properties
    
    fileprivate let rootItem: BulletinItem

    fileprivate var itemsStack: [BulletinItem]
    fileprivate var currentItem: BulletinItem
    fileprivate var previousItem: BulletinItem?

    fileprivate var isPrepared: Bool = false
    fileprivate var isPreparing: Bool = false

    // MARK: - Initialization

    /**
     * Creates a bulletin manager with the first item to display. An item represents the contents
     * displayed on a single card.
     *
     * - parameter rootItem: The first item to display.
     */

    @objc public init(rootItem: BulletinItem) {

        self.rootItem = rootItem
        self.itemsStack = []
        self.currentItem = rootItem

    }

    @available(*, unavailable, message: "BulletinManager.init is unavailable. Use init(rootItem:) instead.")
    override init() {
        fatalError("BulletinManager.init is unavailable. Use init(rootItem:) instead.")
    }

}

// MARK: - Interacting with the Bulletin

extension BulletinManager {

    /**
     * Prepares the bulletin interface and displays the root item.
     *
     * This method must be called before any other interaction with the bulletin.
     */

    @objc public func prepare() {

        assertIsMainThread()

        viewController = BulletinViewController()
        viewController.manager = self

        viewController.modalPresentationStyle = .overFullScreen
        viewController.transitioningDelegate = viewController
        viewController.loadBackgroundView()
        viewController.setNeedsStatusBarAppearanceUpdate()

        isPrepared = true
        isPreparing = true

        refreshCurrentItemInterface()
        isPreparing = false

    }

    /**
     * Performs an operation with the bulletin content view and returns the result.
     *
     * Use this as an opportunity to customize the behavior of the content view (e.g. add motion effects).
     *
     * You must not store a reference to the view, or modify its layout (add subviews, add contraints, ...) as this
     * could break the bulletin.
     *
     * Use this feature sparingly.
     *
     * - parameter transform: The code to execute with the content view.
     * - warning: If you save the content view outside of the `transform` closure, an exception will be raised.
     */

    @discardableResult
    public func withContentView<Result>(_ transform: (UIView) throws -> Result) rethrows -> Result {

        assertIsPrepared()
        assertIsMainThread()

        let contentView = viewController.contentView
        let initialRetainCount = CFGetRetainCount(contentView)

        let result = try transform(viewController.contentView)
        let finalRetainCount = CFGetRetainCount(contentView)

        precondition(initialRetainCount == finalRetainCount,
                     "The content view was saved outside of the transform closure. This is not allowed.")

        return result

    }

    /**
     * Hides the contents of the stack and displays a black activity indicator view.
     *
     * Use this method if you need to perform a long task or fetch some data before changing the item.
     *
     * Displaying the loading indicator does not change the height of the page or the current item.
     *
     * Call one of `push(item:)`, `popItem` or `popToRootItem` to hide the activity indicator and change the current item.
     */

    @objc public func displayActivityIndicator(color: UIColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)) {

        assertIsPrepared()
        assertIsMainThread()

        viewController.displayActivityIndicator(color: color)

    }

    /**
     * Displays a new item after the current one.
     * - parameter item: The item to display.
     */

    @objc public func push(item: BulletinItem) {

        assertIsPrepared()
        assertIsMainThread()

        previousItem = currentItem
        itemsStack.append(item)

        currentItem = item
        refreshCurrentItemInterface()

    }

    /**
     * Removes the current item from the stack and displays the previous item.
     */

    @objc public func popItem() {

        assertIsPrepared()
        assertIsMainThread()

        guard let previousItem = itemsStack.popLast() else {
            popToRootItem()
            return
        }

        self.previousItem = previousItem

        guard let currentItem = itemsStack.last else {
            popToRootItem()
            return
        }

        self.currentItem = currentItem
        refreshCurrentItemInterface()

    }

    /**
     * Removes all the items from the stack and displays the root item.
     */

    @objc public func popToRootItem() {

        assertIsPrepared()
        assertIsMainThread()

        guard currentItem !== rootItem else {
            return
        }

        previousItem = currentItem
        currentItem = rootItem

        itemsStack = []

        refreshCurrentItemInterface()

    }

    /**
     * Displays the next item, if the `nextItem` property of the current item is set.
     *
     * - warning: If you call this method but `nextItem` is `nil`, this will crash your app.
     */

    @objc public func displayNextItem() {

        guard let nextItem = currentItem.nextItem else {
            preconditionFailure("Calling BulletinManager.displayNextItem, but the current item has no nextItem.")
        }

        push(item: nextItem)

    }

}

// MARK: - Presentation / Dismissal

extension BulletinManager {

    /**
     * Presents the bulletin above the specified view controller.
     *
     * - parameter presentingVC: The view controller to use to present the bulletin.
     * - parameter animated: Whether to animate presentation. Defaults to `true`.
     * - parameter completion: An optional block to execute after presentation. Default to `nil`.
     */

    @objc(presentBulletinAboveViewController:animated:completion:)
    public func presentBulletin(above presentingVC: UIViewController,
                                      animated: Bool = true,
                                      completion: (() -> Void)? = nil) {

        assertIsPrepared()
        assertIsMainThread()

        viewController.modalPresentationCapturesStatusBarAppearance = true
        presentingVC.present(viewController, animated: animated, completion: completion)

    }

    /**
     * Dismisses the bulletin and clears the current page. You will have to call `prepare` before
     * presenting the bulletin again.
     *
     * This method will call the `dismissalHandler` block of the current item if it was set.
     *
     * - parameter animated: Whether to animate dismissal. Defaults to `true`.
     */

    @objc(dismissBulletinAnimated:)
    public func dismissBulletin(animated: Bool = true) {

        assertIsPrepared()
        assertIsMainThread()

        currentItem.tearDown()
        currentItem.manager = nil

        viewController.dismiss(animated: animated) {
            self.completeDismissal()
        }

        isPrepared = false

    }

    /**
     * Tears down the view controller and item stack after dismissal is finished.
     */

    @nonobjc func completeDismissal() {

        currentItem.dismissalHandler?(currentItem)

        for arrangedSubview in viewController.contentStackView.arrangedSubviews {
            viewController.contentStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        viewController.backgroundView = nil
        viewController.manager = nil
        viewController.transitioningDelegate = nil

        viewController = nil

        currentItem = self.rootItem
        tearDownItemsChain(startingAt: self.rootItem)

        for item in itemsStack {
            tearDownItemsChain(startingAt: item)
        }

        itemsStack.removeAll()

    }

}

// MARK: - Transitions

extension BulletinManager {

    /// Refreshes the interface for the current item.
    fileprivate func refreshCurrentItemInterface() {

        viewController.isDismissable = false
        viewController.refreshSwipeInteractionController()

        // Tear down old item

        let oldArrangedSubviews = viewController.contentStackView.arrangedSubviews
        let oldHideableArrangedSubviews = recursiveArrangedSubviews(in: oldArrangedSubviews)

        previousItem?.tearDown()
        previousItem?.manager = nil
        previousItem = nil

        currentItem.manager = self

        // Create new views

        let newArrangedSubviews = currentItem.makeArrangedSubviews()
        let newHideableArrangedSubviews = recursiveArrangedSubviews(in: newArrangedSubviews)

        for arrangedSubview in newHideableArrangedSubviews {
            arrangedSubview.isHidden = isPreparing ? false : true
        }

        for arrangedSubview in newArrangedSubviews {
            viewController.contentStackView.addArrangedSubview(arrangedSubview)
        }

        // Animate transition

        let animationDuration = isPreparing ? 0 : 0.75
        let transitionAnimationChain = AnimationChain(duration: animationDuration)

        let hideSubviewsAnimationPhase = AnimationPhase(relativeDuration: 1/3, curve: .linear)

        hideSubviewsAnimationPhase.block = {

            self.viewController.hideActivityIndicator()

            for arrangedSubview in oldArrangedSubviews {
                arrangedSubview.alpha = 0
            }

            for arrangedSubview in newArrangedSubviews {
                arrangedSubview.alpha = 0
            }

        }

        let displayNewItemsAnimationPhase = AnimationPhase(relativeDuration: 1/3, curve: .linear)

        displayNewItemsAnimationPhase.block = {

            for arrangedSubview in oldHideableArrangedSubviews {
                arrangedSubview.isHidden = true
            }

            for arrangedSubview in newHideableArrangedSubviews {
                arrangedSubview.isHidden = false
            }

        }

        displayNewItemsAnimationPhase.completionHandler = {
            self.viewController.contentStackView.alpha = 1
        }

        let finalAnimationPhase = AnimationPhase(relativeDuration: 1/3, curve: .linear)

        finalAnimationPhase.block = {

            for arrangedSubview in newArrangedSubviews {
                arrangedSubview.alpha = 1
            }

        }

        finalAnimationPhase.completionHandler = {

            self.viewController.isDismissable = self.currentItem.isDismissable

            for arrangedSubview in oldArrangedSubviews {
                self.viewController.contentStackView.removeArrangedSubview(arrangedSubview)
                arrangedSubview.removeFromSuperview()
            }

            UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, newArrangedSubviews.first)

        }

        transitionAnimationChain.add(hideSubviewsAnimationPhase)
        transitionAnimationChain.add(displayNewItemsAnimationPhase)
        transitionAnimationChain.add(finalAnimationPhase)

        transitionAnimationChain.start()

    }

    /// Tears down every item on the stack starting from the specified item.
    fileprivate func tearDownItemsChain(startingAt item: BulletinItem) {

        item.tearDown()
        item.manager = nil

        if let nextItem = item.nextItem {
            tearDownItemsChain(startingAt: nextItem)
            item.nextItem = nil
        }

    }

    /// Returns all the arranged subviews.
    private func recursiveArrangedSubviews(in views: [UIView]) -> [UIView] {

        var arrangedSubviews: [UIView] = []

        for view in views {

            if let stack = view as? UIStackView {
                arrangedSubviews.append(stack)
                let recursiveViews = self.recursiveArrangedSubviews(in: stack.arrangedSubviews)
                arrangedSubviews.append(contentsOf: recursiveViews)
            } else {
                arrangedSubviews.append(view)
            }

        }

        return arrangedSubviews

    }

}

// MARK: - Utilities

extension BulletinManager {

    fileprivate func assertIsMainThread() {
        precondition(Thread.isMainThread, "BulletinManager must only be used from the main thread.")
    }

    fileprivate func assertIsPrepared() {
        precondition(isPrepared, "You must call the `prepare` function before interacting with the bulletin.")
    }

}
