//
//  SceneDelegate.swift
//  HospitalApp
//
//  Created by Duane Homick on 2026-01-28.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)

        // Map tab
        let mapVC = LandingPageViewController()
        // Do not set a navigation title; keep the nav bar but with no title text.
        let mapNav = UINavigationController(rootViewController: mapVC)
        mapNav.tabBarItem = UITabBarItem(title: "Map", image: UIImage(systemName: "map"), selectedImage: UIImage(systemName: "map.fill"))

        // List tab
        let listVC = CareCentersListViewController()
        // Keep a title for the list, or remove if you also prefer none.
        listVC.title = "List"
        let listNav = UINavigationController(rootViewController: listVC)
        listNav.tabBarItem = UITabBarItem(title: "List", image: UIImage(systemName: "list.bullet"), selectedImage: UIImage(systemName: "list.bullet"))

        let tab = UITabBarController()
        tab.viewControllers = [mapNav, listNav]

        window.rootViewController = tab
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
    }

    func sceneWillResignActive(_ scene: UIScene) {
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
    }
}

