#pragma once

#include "settings_model.h"

namespace agentmeter {

void load_dashboard_preferences(DashboardPreferences& preferences);
bool save_dashboard_preferences(const DashboardPreferences& preferences);

}  // namespace agentmeter
