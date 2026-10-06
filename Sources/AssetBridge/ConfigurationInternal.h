#pragma once

#import "PrivateAPI.h"

NS_ASSUME_NONNULL_BEGIN

// Use the same configuration manager to validate explicit usages and aliases
id<ParedConfigurationManagerAPI> _Nullable ParedConfigurationManager(void);
id<ParedAssetSetConfigurationAPI> _Nullable ParedAssetSetWithManager(
    id<ParedConfigurationManagerAPI> _Nullable manager, NSString *name);
BOOL ParedEnabledUsagesMatchConfiguration(
    ParedAssetSetUsages *sets, id<ParedConfigurationManagerAPI> manager);
ParedAssetSetUsages *_Nullable ParedResolveAliasWithManager(
    id<ParedConfigurationManagerAPI> _Nullable manager, NSString *alias,
    NSString *value);

NS_ASSUME_NONNULL_END
