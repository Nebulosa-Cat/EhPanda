//
//  SettingStore.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 3/12/31.
//

import ComposableArchitecture

struct SettingState: Equatable {
    enum Route: Int, Hashable, Identifiable, CaseIterable {
        var id: Int { rawValue }

        case account
        case general
        case appearance
        case reading
        case laboratory
        case ehpanda
    }

    // AppEnvStorage
    @BindableState var setting = Setting()
    var tagTranslator = TagTranslator()
    var user = User()

    @BindableState var route: Route?
    var tagTranslatorLoadingState: LoadingState = .idle

    var accountSettingState = AccountSettingState()
    var generalSettingState = GeneralSettingState()
    var appearanceSettingState = AppearanceSettingState()

    mutating func setGreeting(_ greeting: Greeting) {
        guard let currDate = greeting.updateTime else { return }

        if let prevGreeting = user.greeting,
           let prevDate = prevGreeting.updateTime,
           prevDate < currDate
        {
            user.greeting = greeting
        } else if user.greeting == nil {
            user.greeting = greeting
        }
    }
    mutating func updateUser(_ user: User) {
        if let displayName = user.displayName {
            self.user.displayName = displayName
        }
        if let avatarURL = user.avatarURL {
            self.user.avatarURL = avatarURL
        }
        if let galleryPoints = user.galleryPoints,
           let credits = user.credits
        {
            self.user.galleryPoints = galleryPoints
            self.user.credits = credits
        }
    }
}

enum SettingAction: BindableAction {
    case binding(BindingAction<SettingState>)
    case setNavigation(SettingState.Route?)
    case clearSubStates

    case syncAppIconType
    case syncUserInterfaceStyle
    case syncSetting
    case syncTagTranslator
    case syncUser

    case loadUserSettings
    case onLoadUserSettings(AppEnv)
    case loadUserSettingsDone
    case createDefaultEhProfile
    case fetchIgneous
    case fetchIgneousDone(Result<HTTPURLResponse, AppError>)
    case fetchUserInfo
    case fetchUserInfoDone(Result<User, AppError>)
    case fetchGreeting
    case fetchGreetingDone(Result<Greeting, AppError>)
    case fetchTagTranslator
    case fetchTagTranslatorDone(Result<TagTranslator, AppError>)
    case fetchEhProfileIndex
    case fetchEhProfileIndexDone(Result<(Int?, Bool), AppError>)
    case fetchFavoriteCategories
    case fetchFavoriteCategoriesDone(Result<[Int: String], AppError>)

    case account(AccountSettingAction)
    case general(GeneralSettingAction)
    case appearance(AppearanceSettingAction)
}

struct SettingEnvironment {
    let dfClient: DFClient
    let fileClient: FileClient
    let deviceClient: DeviceClient
    let loggerClient: LoggerClient
    let hapticClient: HapticClient
    let libraryClient: LibraryClient
    let cookiesClient: CookiesClient
    let databaseClient: DatabaseClient
    let clipboardClient: ClipboardClient
    let appDelegateClient: AppDelegateClient
    let userDefaultsClient: UserDefaultsClient
    let uiApplicationClient: UIApplicationClient
    let authorizationClient: AuthorizationClient
}

let settingReducer = Reducer<SettingState, SettingAction, SettingEnvironment>.combine(
    .init { state, action, environment in
        switch action {
        case .binding(\.$setting.galleryHost):
            return .merge(
                .init(value: .syncSetting),
                environment.userDefaultsClient
                    .setValue(state.setting.galleryHost.rawValue, .galleryHost).fireAndForget()
            )

        case .binding(\.$setting.enablesTagsExtension):
            var effects: [Effect<SettingAction, Never>] = [
                .init(value: .syncSetting)
            ]
            if state.setting.enablesTagsExtension {
                effects.append(.init(value: .fetchTagTranslator))
            }
            return .merge(effects)

        case .binding(\.$setting.preferredColorScheme):
            return .merge(
                .init(value: .syncSetting),
                .init(value: .syncUserInterfaceStyle)
            )

        case .binding(\.$setting.appIconType):
            return .merge(
                .init(value: .syncSetting),
                environment.uiApplicationClient.setAlternateIconName(state.setting.appIconType.filename)
                    .map { _ in SettingAction.syncAppIconType }
            )

        case .binding(\.$setting.autoLockPolicy):
            if state.setting.autoLockPolicy != .never
                && state.setting.backgroundBlurRadius == 0
            {
                state.setting.backgroundBlurRadius = 10
            }
            return .init(value: .syncSetting)

        case .binding(\.$setting.backgroundBlurRadius):
            if state.setting.autoLockPolicy != .never
                && state.setting.backgroundBlurRadius == 0
            {
                state.setting.autoLockPolicy = .never
            }
            return .init(value: .syncSetting)

        case .binding(\.$setting.enablesLandscape):
            var effects: [Effect<SettingAction, Never>] = [
                .init(value: .syncSetting)
            ]
            if !state.setting.enablesLandscape && !environment.deviceClient.isPad() {
                effects.append(environment.appDelegateClient.setPortraitOrientationMask().fireAndForget())
            }
            return .merge(effects)

        case .binding(\.$setting.maximumScaleFactor):
            if state.setting.doubleTapScaleFactor > state.setting.maximumScaleFactor {
                state.setting.doubleTapScaleFactor = state.setting.maximumScaleFactor
            }
            return .init(value: .syncSetting)

        case .binding(\.$setting.doubleTapScaleFactor):
            if state.setting.maximumScaleFactor < state.setting.doubleTapScaleFactor {
                state.setting.maximumScaleFactor = state.setting.doubleTapScaleFactor
            }
            return .init(value: .syncSetting)

        case .binding(\.$setting.bypassesSNIFiltering):
            return .merge(
                .init(value: .syncSetting),
                environment.hapticClient.generateFeedback(.soft).fireAndForget(),
                environment.dfClient.setActive(state.setting.bypassesSNIFiltering).fireAndForget()
            )

        case .binding(\.$setting):
            return .init(value: .syncSetting)

        case .binding(\.$route):
            return .none

        case .binding:
            return .merge(
                .init(value: .syncUser),
                .init(value: .syncSetting),
                .init(value: .syncTagTranslator)
            )

        case .setNavigation(let route):
            state.route = route
            return .none

        case .clearSubStates:
            state.accountSettingState = .init()
            state.generalSettingState = .init()
            state.appearanceSettingState = .init()
            return .none

        case .syncAppIconType:
            if let iconName = environment.uiApplicationClient.alternateIconName() {
                state.setting.appIconType = AppIconType.allCases.filter({
                    iconName.contains($0.filename)
                }).first ?? .default
            }
            return .none

        case .syncUserInterfaceStyle:
            let style = state.setting.preferredColorScheme.userInterfaceStyle
            return environment.uiApplicationClient.setUserInterfaceStyle(style)
                .subscribe(on: DispatchQueue.main).fireAndForget()

        case .syncSetting:
            return environment.databaseClient.updateSetting(state.setting).fireAndForget()
        case .syncTagTranslator:
            return environment.databaseClient.updateTagTranslator(state.tagTranslator).fireAndForget()
        case .syncUser:
            return environment.databaseClient.updateUser(state.user).fireAndForget()

        case .loadUserSettings:
            return environment.databaseClient.fetchAppEnv().map(SettingAction.onLoadUserSettings)

        case .onLoadUserSettings(let appEnv):
            state.setting = appEnv.setting
            state.tagTranslator = appEnv.tagTranslator
            state.user = appEnv.user
            var effects: [Effect<SettingAction, Never>] = [
                .init(value: .syncAppIconType),
                .init(value: .loadUserSettingsDone),
                .init(value: .syncUserInterfaceStyle),
                environment.dfClient.setActive(state.setting.bypassesSNIFiltering).fireAndForget()
            ]
            if let value: String = environment.userDefaultsClient.getValue(.galleryHost),
               let galleryHost = GalleryHost(rawValue: value)
            {
                state.setting.galleryHost = galleryHost
            }
            if environment.cookiesClient.shouldFetchIgneous {
                effects.append(.init(value: .fetchIgneous))
            }
            if environment.cookiesClient.didLogin {
                effects.append(contentsOf: [
                    .init(value: .fetchUserInfo),
                    .init(value: .fetchGreeting),
                    .init(value: .fetchFavoriteCategories),
                    .init(value: .fetchEhProfileIndex)
                ])
            }
            if state.setting.enablesTagsExtension {
                effects.append(.init(value: .fetchTagTranslator))
            }
            return .merge(effects)

        case .loadUserSettingsDone:
            return .none

        case .createDefaultEhProfile:
            return EhProfileRequest(action: .create, name: "EhPanda").effect.fireAndForget()

        case .fetchIgneous:
            guard environment.cookiesClient.didLogin else { return .none }
            return IgneousRequest().effect.map(SettingAction.fetchIgneousDone)

        case .fetchIgneousDone(let result):
            var effects = [Effect<SettingAction, Never>]()
            if case .success(let response) = result {
                effects.append(environment.cookiesClient.setCredentials(response: response).fireAndForget())
            }
            effects.append(.init(value: .account(.loadCookies)))
            return .merge(effects)

        case .fetchUserInfo:
            guard environment.cookiesClient.didLogin else { return .none }
            let uid = environment.cookiesClient
                .getCookie(Defaults.URL.host, Defaults.Cookie.ipbMemberId).rawValue
            if !uid.isEmpty {
                return UserInfoRequest(uid: uid).effect.map(SettingAction.fetchUserInfoDone)
            }
            return .none

        case .fetchUserInfoDone(let result):
            if case .success(let user) = result {
                state.updateUser(user)
                return .init(value: .syncUser)
            }
            return .none

        case .fetchGreeting:
            func verifyDate(with updateTime: Date?) -> Bool {
                guard let updateTime = updateTime else { return true }

                let currentTime = Date()
                let formatter = DateFormatter()
                formatter.locale = Locale.current
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = Defaults.DateFormat.greeting

                let currentTimeString = formatter.string(from: currentTime)
                if let currentDay = formatter.date(from: currentTimeString) {
                    return currentTime > currentDay && updateTime < currentDay
                }

                return false
            }

            guard environment.cookiesClient.didLogin,
                  state.setting.showsNewDawnGreeting
            else { return .none }
            let requestEffect = GreetingRequest().effect
                .map(SettingAction.fetchGreetingDone)
            if let greeting = state.user.greeting {
                if verifyDate(with: greeting.updateTime) {
                    return requestEffect
                }
            } else {
                return requestEffect
            }
            return .none

        case .fetchGreetingDone(let result):
            switch result {
            case .success(let greeting):
                state.setGreeting(greeting)
                return .init(value: .syncUser)
            case .failure(let error):
                if case .parseFailed = error {
                    var greeting = Greeting()
                    greeting.updateTime = Date()
                    state.setGreeting(greeting)
                    return .init(value: .syncUser)
                }
            }
            return .none

        case .fetchTagTranslator:
            guard state.tagTranslatorLoadingState != .loading,
                  !state.tagTranslator.hasCustomTranslations,
                  let language = TranslatableLanguage.current
            else { return .none }
            state.tagTranslatorLoadingState = .loading

            var databaseEffect: Effect<SettingAction, Never>?
            if state.tagTranslator.language != language {
                state.tagTranslator = TagTranslator(language: language)
                databaseEffect = .init(value: .syncTagTranslator)
            }
            let updatedDate = state.tagTranslator.updatedDate
            let requestEffect = TagTranslatorRequest(language: language, updatedDate: updatedDate)
                .effect.map(SettingAction.fetchTagTranslatorDone)
            if let databaseEffect = databaseEffect {
                return .merge(databaseEffect, requestEffect)
            } else {
                return requestEffect
            }

        case .fetchTagTranslatorDone(let result):
            state.tagTranslatorLoadingState = .idle
            switch result {
            case .success(let tagTranslator):
                state.tagTranslator = tagTranslator
                return .init(value: .syncTagTranslator)
            case .failure(let error):
                state.tagTranslatorLoadingState = .failed(error)
            }
            return .none

        case .fetchEhProfileIndex:
            guard environment.cookiesClient.didLogin else { return .none }
            return VerifyEhProfileRequest().effect.map(SettingAction.fetchEhProfileIndexDone)

        case .fetchEhProfileIndexDone(let result):
            var effects = [Effect<SettingAction, Never>]()

            if case .success(let (profileValue, profileNotFound)) = result {
                if let profileValue = profileValue {
                    let hostURL = Defaults.URL.host
                    let profileValueString = String(profileValue)
                    let selectedProfileKey = Defaults.Cookie.selectedProfile

                    let cookieValue =  environment.cookiesClient.getCookie(hostURL, selectedProfileKey)
                    if cookieValue.rawValue != profileValueString {
                        effects.append(
                            environment.cookiesClient.setOrEditCookie(
                                for: hostURL, key: selectedProfileKey, value: profileValueString
                            )
                            .fireAndForget()
                        )
                    }
                } else if profileNotFound {
                    effects.append(.init(value: .createDefaultEhProfile))
                } else {
                    let message = "Found profile but failed in parsing value."
                    effects.append(environment.loggerClient.error(message, nil).fireAndForget())
                }
            }
            return effects.isEmpty ? .none : .merge(effects)

        case .fetchFavoriteCategories:
            guard environment.cookiesClient.didLogin else { return .none }
            return FavoriteCategoriesRequest().effect.map(SettingAction.fetchFavoriteCategoriesDone)

        case .fetchFavoriteCategoriesDone(let result):
            if case .success(let categories) = result {
                state.user.favoriteCategories = categories
            }
            return .none

        case .account(.login(.loginDone)):
            return .merge(
                environment.cookiesClient.removeYay().fireAndForget(),
                environment.cookiesClient.fulfillAnotherHostField().fireAndForget(),
                .init(value: .fetchIgneous),
                .init(value: .fetchUserInfo),
                .init(value: .fetchFavoriteCategories),
                .init(value: .fetchEhProfileIndex)
            )

        case .account(.onLogoutConfirmButtonTapped):
            state.user = User()
            return .merge(
                .init(value: .syncUser),
                environment.cookiesClient.clearAll().fireAndForget(),
                environment.databaseClient.removeImageURLs().fireAndForget(),
                environment.libraryClient.clearWebImageDiskCache().fireAndForget()
            )

        case .account:
            return .none

        case .general(.onTranslationsFilePicked(let url)):
            return environment.fileClient.importTagTranslator(url).map(SettingAction.fetchTagTranslatorDone)

        case .general(.onRemoveCustomTranslations):
            state.tagTranslator.hasCustomTranslations = false
            state.tagTranslator.translations = .init()
            return .init(value: .syncTagTranslator)

        case .general:
            return .none

        case .appearance:
            return .none
        }
    }
    .binding(),
    accountSettingReducer.pullback(
        state: \.accountSettingState,
        action: /SettingAction.account,
        environment: {
            .init(
                hapticClient: $0.hapticClient,
                cookiesClient: $0.cookiesClient,
                clipboardClient: $0.clipboardClient,
                uiApplicationClient: $0.uiApplicationClient
            )
        }
    ),
    generalSettingReducer.pullback(
        state: \.generalSettingState,
        action: /SettingAction.general,
        environment: {
            .init(
                fileClient: $0.fileClient,
                loggerClient: $0.loggerClient,
                libraryClient: $0.libraryClient,
                databaseClient: $0.databaseClient,
                uiApplicationClient: $0.uiApplicationClient,
                authorizationClient: $0.authorizationClient
            )
        }
    ),
    appearanceSettingReducer.pullback(
        state: \.appearanceSettingState,
        action: /SettingAction.appearance,
        environment: { _ in
            .init()
        }
    )
)
