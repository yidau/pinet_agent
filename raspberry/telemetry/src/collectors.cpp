#include "collectors.hpp"
#include <openssl/sha.h>

#include <algorithm>
#include <charconv>
#include <cmath>
#include <fstream>
#include <limits>
#include <locale>
#include <memory>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string_view>
#include <utility>

#include <curl/curl.h>
#include <nlohmann/json.hpp>

namespace pocketnet::telemetry {
namespace {

using Json = nlohmann::json;
namespace fs = std::filesystem;
using Clock = std::chrono::steady_clock;
constexpr std::size_t kResponseLimit = 1024 * 1024;
constexpr size_t kAccessPointLimit = 128;
constexpr size_t kClientLimit = 256;
constexpr size_t kDeviceLimit = kAccessPointLimit + kClientLimit;
constexpr size_t kDevicePageSize = 64;
constexpr size_t kPriorityLimit = 8;
constexpr auto kRequestTimeout = std::chrono::milliseconds(1200);

int64_t unixMillis() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

template <typename T>
std::optional<T> integer(std::string_view value) {
    T result{};
    const auto converted = std::from_chars(value.data(), value.data() + value.size(), result);
    if (converted.ec != std::errc{} || converted.ptr != value.data() + value.size()) {
        return std::nullopt;
    }
    return result;
}

std::ifstream input(const fs::path& path) {
    std::ifstream stream(path, std::ios::binary);
    stream.imbue(std::locale::classic());
    return stream;
}

std::string readWord(const fs::path& path) {
    std::string word;
    auto stream = input(path);
    stream.width(128);
    stream >> word;
    return word;
}

std::vector<fs::path> children(const fs::path& path) {
    std::vector<fs::path> result;
    std::error_code error;
    for (fs::directory_iterator item(path, error); !error && item != fs::directory_iterator{}; item.increment(error)) {
        result.push_back(item->path());
    }
    return result;
}

template <size_t Count>
std::optional<std::array<uint64_t, Count>> readCounters(std::istream& fields) {
    std::array<uint64_t, Count> sample{};
    for (auto& counter : sample) {
        std::string value;
        if (!(fields >> value)) return std::nullopt;
        auto parsed = integer<uint64_t>(value);
        if (!parsed) return std::nullopt;
        counter = *parsed;
    }
    return sample;
}

std::optional<std::array<uint64_t, 8>> readCpu(const fs::path& path) {
    auto stream = input(path);
    std::string line;
    if (!std::getline(stream, line)) return std::nullopt;
    std::istringstream fields(line);
    std::string label;
    fields >> label;
    if (label != "cpu") return std::nullopt;
    return readCounters<8>(fields);
}

std::map<std::string, uint64_t> readMemory(const fs::path& path) {
    auto stream = input(path);
    std::map<std::string, uint64_t> result;
    for (std::string line; std::getline(stream, line);) {
        std::istringstream fields(line);
        std::string key, value, unit;
        if (!(fields >> key >> value >> unit) || unit != "kB") continue;
        if (key != "MemTotal:" && key != "MemAvailable:" && key != "SwapTotal:" && key != "SwapFree:") continue;
        if (auto kib = integer<uint64_t>(value); kib && *kib <= std::numeric_limits<uint64_t>::max() / 1024) {
            result.emplace(std::move(key), *kib * 1024);
        }
    }
    return result;
}

std::optional<float> readTemperature(const fs::path& sys) {
    std::optional<int64_t> hottest;
    for (const auto& dir : children(sys / "class/thermal")) {
        if (dir.filename().string().rfind("thermal_zone", 0) != 0) continue;
        auto type = readWord(dir / "type");
        if (type != "cpu-thermal" && type != "cpu_thermal" && type != "x86_pkg_temp"
            && type != "soc_thermal" && type != "soc-thermal") continue;
        auto value = integer<int64_t>(readWord(dir / "temp"));
        if (value && *value >= -100000 && *value <= 200000 && (!hottest || *value > *hottest)) {
            hottest = value;
        }
    }
    if (!hottest) return std::nullopt;
    return static_cast<float>(*hottest) / 1000.0F;
}

std::optional<float> readFrequency(const fs::path& sys) {
    double sum = 0;
    unsigned count = 0;
    for (const auto& dir : children(sys / "devices/system/cpu/cpufreq")) {
        if (dir.filename().string().rfind("policy", 0) != 0) continue;
        auto frequency = integer<uint64_t>(readWord(dir / "cpuinfo_cur_freq"));
        if (!frequency || *frequency == 0) {
            frequency = integer<uint64_t>(readWord(dir / "scaling_cur_freq"));
        }
        if (frequency && *frequency > 0) {
            sum += static_cast<double>(*frequency);
            ++count;
        }
    }
    if (!count) return std::nullopt;
    return static_cast<float>(sum / count / 1000);
}

std::optional<float> pressurePercentage(std::string_view str) {
    std::istringstream fields{std::string(str)};
    fields.imbue(std::locale::classic());
    float value = 0;
    if (!(fields >> value) || !fields.eof() || !std::isfinite(value) || value < 0 || value > 100) {
        return std::nullopt;
    }
    return value;
}

v1::Pressure readPressure(const fs::path& file, bool includeFull) {
    v1::Pressure pressure;
    auto stream = input(file);
    for (std::string line; std::getline(stream, line);) {
        std::istringstream fields(line);
        std::string key;
        fields >> key;
        if (key != "some" && (key != "full" || !includeFull)) continue;
        for (std::string token; fields >> token;) {
            const auto avg10 = token.rfind("avg10=", 0) == 0;
            if (!avg10 && token.rfind("avg60=", 0) != 0) continue;
            auto value = pressurePercentage(std::string_view(token).substr(6));
            if (!value) continue;
            if (key == "some") {
                if (avg10) pressure.set_some_avg10(*value);
                else pressure.set_some_avg60(*value);
            } else {
                if (avg10) pressure.set_full_avg10(*value);
                else pressure.set_full_avg60(*value);
            }
        }
    }
    return pressure;
}

std::map<std::string, std::array<uint64_t, 5>> readDisks(const fs::path& path, const fs::path& sys) {
    auto stream = input(path);
    std::map<std::string, std::array<uint64_t, 5>> result;
    for (std::string line; std::getline(stream, line);) {
        std::istringstream fields(line);
        std::string major, minor, name;
        if (!(fields >> major >> minor >> name)) continue;
        if (!integer<uint64_t>(major) || !integer<uint64_t>(minor)
            || name.find('/') != std::string::npos || name == "." || name == "..") continue;
        std::error_code error;
        auto device = fs::canonical(sys / "block" / name, error);
        if (error || device.generic_string().find("/devices/virtual/") != std::string::npos) continue;
        if (auto rates = readCounters<10>(fields)) {
            const auto& values = *rates;
            result.emplace(major + ":" + minor + ":" + name, std::array<uint64_t, 5>{
                values[0], values[2], values[4], values[6], values[9],
            });
        }
    }
    return result;
}

template <typename T>
std::optional<std::array<double, std::tuple_size<T>::value>> deltas(const T& old, const T& current) {
    std::array<double, std::tuple_size<T>::value> result{};
    for (size_t i = 0; i < current.size(); ++i) {
        if (current[i] < old[i]) return std::nullopt;
        result[i] = static_cast<double>(current[i] - old[i]);
    }
    return result;
}

const Json& field(const Json& object, const char* key) {
    static const Json missing;
    if (!object.is_object()) return missing;
    const auto found = object.find(key);
    return found == object.end() ? missing : *found;
}

std::string string(const Json& value, size_t limit) {
    if (!value.is_string()) return {};
    const auto& result = value.get_ref<const std::string&>();
    if (result.size() > limit || std::any_of(result.begin(), result.end(), [](unsigned char c) {
            return c < 0x20 || c == 0x7f;
        })) return {};
    return result;
}

std::optional<uint64_t> unsignedNumber(const Json& value) {
    if (value.is_number_unsigned()) return value.get<uint64_t>();
    if (value.is_number_integer()) {
        const auto number = value.get<int64_t>();
        if (number >= 0) return static_cast<uint64_t>(number);
    }
    return std::nullopt;
}

std::optional<double> number(const Json& value) {
    if (!value.is_number()) return std::nullopt;
    const double result = value.get<double>();
    if (!std::isfinite(result)) return std::nullopt;
    return result;
}

std::optional<bool> flag(const Json& value) {
    if (value.is_boolean()) return value.get<bool>();
    auto parsed = unsignedNumber(value);
    if (parsed && *parsed <= 1) return *parsed == 1;
    return std::nullopt;
}

bool hexDigit(char c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

std::string canonicalKey(const Json& value, std::string_view pattern, char separator) {
    std::string result = string(value, pattern.size());
    if (result.size() != pattern.size()) return {};
    for (size_t i = 0; i < result.size(); ++i) {
        if (pattern[i] == separator ? result[i] != separator : !hexDigit(result[i])) return {};
        if (result[i] >= 'A' && result[i] <= 'F') result[i] += 'a' - 'A';
    }
    return result;
}

std::string uuid(const Json& value) {
    return canonicalKey(value, "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", '-');
}

std::string mac(const Json& value) {
    auto address = canonicalKey(value, "xx:xx:xx:xx:xx:xx", ':');
    // Null and group addresses do not identify an access point or a client.
    if (address.empty() || address == "00:00:00:00:00:00") return {};
    auto low = address[1];
    auto digit = low <= '9' ? low - '0' : low - 'a' + 10;
    return digit % 2 ? std::string{} : address;
}

Json parseJson(const std::string& text) {
    auto checkDepth = [](int depth, auto, auto&) {
        if (depth > 48) throw std::length_error("Kismet JSON nesting exceeds limit");
        return true;
    };
    try {
        return Json::parse(text, checkDepth, false);
    } catch (const std::length_error&) {
        return {};
    }
}

bool loopbackUrl(const std::string& url) {
    const auto start = url.rfind("http://", 0) == 0 ? 7U : (url.rfind("https://", 0) == 0 ? 8U : 0U);
    if (!start) return false;
    auto authority = std::string_view(url).substr(start);
    size_t prefix = authority.rfind("127.0.0.1:", 0) == 0 ? 10U : (authority.rfind("[::1]:", 0) == 0 ? 6U : 0U);
    if (!prefix) return false;
    authority.remove_prefix(prefix);
    const auto port = integer<unsigned>(authority);
    return port && *port > 0 && *port <= 65535;
}

bool validApiKey(const std::string& key) {
    if (key.empty() || key.size() > 512) return false;
    return std::all_of(key.begin(), key.end(), [](char c) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
            || std::string_view("._~+/=-").find(c) != std::string_view::npos;
    });
}

size_t collectBody(char* ptr, size_t size, size_t count, void* user) {
    const auto length = size * count;
    auto& body = *static_cast<std::string*>(user);
    if (length > kResponseLimit - body.size()) return 0;
    try {
        body.append(ptr, length);
    } catch (...) {
        return 0;
    }
    return length;
}

struct Response {
    Json data;
    long status = 0;
    bool reachable = false;
};

struct DevicePage {
    size_t offset;
    size_t length;
};

Response request(const std::string& base, const std::string& key, const std::string& path,
                 const Json& form = Json(), std::optional<DevicePage> page = std::nullopt,
                 std::chrono::milliseconds timeout = kRequestTimeout) {
    static const bool curlReady = curl_global_init(CURL_GLOBAL_DEFAULT) == CURLE_OK;
    if (!curlReady) return {};
    std::unique_ptr<CURL, decltype(&curl_easy_cleanup)> client(curl_easy_init(), curl_easy_cleanup);
    if (!client) return {};
    const auto url = base + path;
    const auto port = base.substr(base.rfind(':') + 1);
    const auto cookie = "KISMET=" + key + "; KISMET_" + port + "=" + key;
    std::string response, post;
    curl_easy_setopt(client.get(), CURLOPT_URL, url.c_str());
    curl_easy_setopt(client.get(), CURLOPT_COOKIE, cookie.c_str());
    curl_easy_setopt(client.get(), CURLOPT_PROXY, "");
    curl_easy_setopt(client.get(), CURLOPT_FOLLOWLOCATION, 0L);
    curl_easy_setopt(client.get(), CURLOPT_CONNECTTIMEOUT_MS, 400L);
    curl_easy_setopt(client.get(), CURLOPT_TIMEOUT_MS, static_cast<long>(timeout.count()));
    curl_easy_setopt(client.get(), CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(client.get(), CURLOPT_WRITEFUNCTION, collectBody);
    curl_easy_setopt(client.get(), CURLOPT_WRITEDATA, &response);
    if (!form.is_null()) {
        auto raw = form.dump();
        std::unique_ptr<char, decltype(&curl_free)> encoded(
            curl_easy_escape(client.get(), raw.data(), static_cast<int>(raw.size())), curl_free);
        if (!encoded) return {};
        post = "json=" + std::string(encoded.get());
        if (page) {
            post += "&draw=1&start=" + std::to_string(page->offset)
                + "&length=" + std::to_string(page->length);
        }
        curl_easy_setopt(client.get(), CURLOPT_POSTFIELDS, post.c_str());
    }
    const auto result = curl_easy_perform(client.get());
    long status = 0;
    curl_easy_getinfo(client.get(), CURLINFO_RESPONSE_CODE, &status);
    return {result == CURLE_OK && status == 200 ? parseJson(response) : Json{}, status, status != 0};
}

struct MonitorState {
    std::string state;
    std::string reason;
    std::string source;
    std::string epoch;
    std::string profile;
    bool pause_requested = false;
};

MonitorState readMonitor(const fs::path& path, int64_t now) {
    auto file = input(path);
    if (!file) return {"unconfigured", "monitor_not_configured", {}};
    std::array<char, 4097> buffer{};
    file.read(buffer.data(), buffer.size());
    const auto size = file.gcount();
    if (file.bad() || size == static_cast<std::streamsize>(buffer.size())) {
        return {"degraded", "monitor_state_invalid", {}};
    }
    const auto doc = parseJson(std::string(buffer.data(), static_cast<size_t>(size)));
    const auto timestamp = unsignedNumber(field(doc, "timestamp_ms"));
    const auto tick = unsignedNumber(field(doc, "boottime_ns"));
    const auto monotonic = std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now().time_since_epoch()).count();
    const bool stale = tick ? (*tick > static_cast<std::uint64_t>(monotonic) ||
                                 static_cast<std::uint64_t>(monotonic) - *tick > 30000000000ull)
        : (!timestamp || *timestamp > static_cast<std::uint64_t>(now + 5000) ||
                        *timestamp < static_cast<std::uint64_t>(std::max<int64_t>(now - 30000, 0)));
    if (stale) {
        return {"degraded", "monitor_state_stale", {}};
    }
    const auto state = string(field(doc, "state"), 16);
    const auto reason = string(field(doc, "reason"), 64);
    const auto& paused = field(doc, "pause_requested");
    const bool pause_requested = paused.is_boolean() && paused.get<bool>();
    if (state == "starting" || state == "degraded" || state == "paused")
        return {state, reason, {}, {}, {}, pause_requested};
    const auto source = uuid(field(doc, "datasource_uuid"));
    if (state != "ready" || source.empty()) return {"degraded", "monitor_state_invalid", {}};
    return {state, reason, source, string(field(doc, "observation_epoch"), 64),
            string(field(doc, "actual_profile"), 16)};
}

std::optional<uint64_t> recentRate(const Json& rrd, int64_t now) {
    auto serial = unsignedNumber(field(rrd, "kismet.common.rrd.serial_time"));
    auto last = unsignedNumber(field(rrd, "kismet.common.rrd.last_time"));
    const auto& vec = field(rrd, "kismet.common.rrd.minute_vec");
    if (!serial || !last || *serial < *last || *serial - *last > 15 || !vec.is_array() || vec.size() != 60
        || now < 1000 || *serial > static_cast<uint64_t>(now / 1000 + 5)
        || *serial + 15 < static_cast<uint64_t>(now / 1000)) return std::nullopt;
    return unsignedNumber(vec[*last % 60]);
}

int64_t secondsMillis(const Json& input, int64_t now) {
    auto seconds = number(input);
    if (!seconds || *seconds <= 0 || *seconds * 1000 > static_cast<double>(now) + 5000) return 0;
    return static_cast<int64_t>(*seconds * 1000);
}

bool exclusivelySeenBy(const Json& row, const std::string& source) {
    const auto& seen = field(row, "kismet.device.base.seenby");
    return (seen.is_object() || seen.is_array()) && seen.size() == 1
        && uuid(field(*seen.begin(), "kismet.common.seenby.uuid")) == source;
}

Json deviceFields(int64_t now) {
    return {
        {"fields", Json::array({
            "kismet.device.base.type", "kismet.device.base.key", "kismet.device.base.phyname",
            "kismet.device.base.macaddr", "kismet.device.base.channel",
            "kismet.device.base.frequency", "kismet.device.base.crypt", "kismet.device.base.first_time",
            "kismet.device.base.last_time", "kismet.device.base.seenby",
            Json::array({"kismet.device.base.signal/kismet.common.signal.type", "signal_type"}),
            Json::array({"kismet.device.base.signal/kismet.common.signal.last_signal", "signal_value"}),
            Json::array({"dot11.device/dot11.device.last_beaconed_ssid_record/dot11.advertisedssid.ssid", "ssid"}),
            Json::array({"dot11.device/dot11.device.last_beaconed_ssid_record/dot11.advertisedssid.cloaked", "ssid_hidden"}),
            Json::array({"dot11.device/dot11.device.last_beaconed_ssid_record/dot11.advertisedssid.crypt_string", "beacon_security"}),
            Json::array({"dot11.device/dot11.device.last_bssid", "last_bssid"}),
            Json::array({"dot11.device/dot11.device.associated_client_map", "associated_clients"}),
            Json::array({"dot11.device/dot11.device.datasize", "data_bytes"}),
        })},
        {"datatable", true},
        {"last_time", std::max<int64_t>(0, now / 1000 - 300)},
    };
}

struct DeviceWindow {
    Json rows = Json::array();
    bool available = false;
    bool limited = false;
};

DeviceWindow readDeviceWindow(const std::string& base, const std::string& key,
                              const std::string& path, const std::string& source, int64_t now) {
    DeviceWindow window;
    const auto fields = deviceFields(now);
    const auto deadline = Clock::now() + kRequestTimeout;
    std::optional<uint64_t> expectedTotal;
    for (size_t offset = 0; offset < kDeviceLimit; offset += kDevicePageSize) {
        const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - Clock::now());
        if (remaining.count() <= 0) break;
        const auto length = std::min(kDevicePageSize, kDeviceLimit - offset);
        auto page = request(base, key, path, fields, DevicePage{offset, length}, remaining).data;
        const auto total = unsignedNumber(field(page, "recordsFiltered"));
        if (!total || !field(page, "data").is_array() || *total < offset) break;
        auto& rows = page.at("data");
        if (rows.size() != std::min<uint64_t>(length, *total - offset)) break;
        if (expectedTotal && *expectedTotal != *total) window.limited = true;
        expectedTotal = total;
        window.available = true;
        for (auto& row : rows) {
            if (string(field(row, "kismet.device.base.phyname"), 24) != "IEEE802.11") continue;
            if (!exclusivelySeenBy(row, source)) {
                window.limited = true;
                continue;
            }
            // Source attribution has been checked. Discard the per-source counters before retaining the row.
            row.erase("kismet.device.base.seenby");
            window.rows.push_back(std::move(row));
        }
        if (offset + rows.size() == *total) return window;
    }
    window.limited = true;
    return window;
}

struct AccessPoint {
    v1::PriorityAP metadata;
    int64_t lastSeen;
};

v1::WirelessSummary summarize(const DeviceWindow& window, int64_t now,
                              KismetSample& sample) {
    v1::WirelessSummary summary;
    if (!window.available) {
        summary.set_coverage("source_view_unavailable");
        return summary;
    }
    std::map<std::string, AccessPoint> aps;
    std::map<std::string, v1::ObservedDevice> clients;
    std::map<std::string, std::string> last_bssids;
    std::map<std::string, const Json*> associations;
    const auto info = [&](const auto& row, const std::string& address, int64_t last_seen) {
        v1::ObservedDevice item;
        const auto key = string(field(row, "kismet.device.base.key"), 96);
        item.set_device_key(key.empty() ? address : key);
        item.set_mac(address);
        item.set_source_scope("managed_monitor");
        const auto channel = string(field(row, "kismet.device.base.channel"), 24);
        if (!channel.empty()) item.set_channel(channel);
        const auto rssi = number(field(row, "signal_value"));
        if (string(field(row, "signal_type"), 12) == "dbm" && rssi && *rssi < 0 && *rssi >= -160) {
            item.set_rssi_dbm(static_cast<float>(*rssi));
        }
        const auto first = secondsMillis(field(row, "kismet.device.base.first_time"), now);
        if (first > 0 && first <= last_seen) item.set_first_seen_ms(first);
        item.set_last_seen_ms(last_seen);
        return item;
    };
    bool limited = window.limited;
    for (const auto& row : window.rows) {
        auto address = mac(field(row, "kismet.device.base.macaddr"));
        if (address.empty()) {
            limited = true;
            continue;
        }
        const auto lastSeen = secondsMillis(field(row, "kismet.device.base.last_time"), now);
        if (lastSeen == 0) {
            limited = true;
            continue;
        }
        // Each snapshot summarizes devices actually seen during the preceding five minutes.
        if (now - lastSeen > 300000) continue;
        const auto type = string(field(row, "kismet.device.base.type"), 32);
        if (type == "Wi-Fi Client" || type == "Wi-Fi Client (Inferred)") {
            if (!clients.count(address) && clients.size() == kClientLimit) {
                limited = true;
                continue;
            }
            auto item = info(row, address, lastSeen);
            item.set_kind(v1::CLIENT);
            item.set_association_state(v1::NOT_ESTABLISHED);
            if (!clients.count(address) || lastSeen > clients.at(address).last_seen_ms()) {
                last_bssids[address] = mac(field(row, "last_bssid"));
                clients.insert_or_assign(address, std::move(item));
            }
        }
        if (type != "Wi-Fi AP") continue;
        if (!aps.count(address) && aps.size() == kAccessPointLimit) {
            limited = true;
            continue;
        }
        v1::PriorityAP ap;
        ap.set_bssid(address);
        if (flag(field(row, "ssid_hidden")) != true) ap.set_ssid(string(field(row, "ssid"), 128));
        ap.set_channel(string(field(row, "kismet.device.base.channel"), 24));
        auto security = string(field(row, "beacon_security"), 96);
        if (security.empty()) security = string(field(row, "kismet.device.base.crypt"), 96);
        ap.set_security(security);
        const auto rssi = number(field(row, "signal_value"));
        if (string(field(row, "signal_type"), 12) == "dbm" && rssi && *rssi < 0 && *rssi >= -160) {
            ap.set_rssi_dbm(static_cast<float>(*rssi));
        }
        const auto frequency = unsignedNumber(field(row, "kismet.device.base.frequency"));
        if (frequency && *frequency > 0) ap.set_frequency_khz(*frequency);
        const auto firstSeen = secondsMillis(field(row, "kismet.device.base.first_time"), now);
        if (firstSeen <= lastSeen) ap.set_first_seen_ms(firstSeen);
        ap.set_last_seen_ms(lastSeen);
        auto existing = aps.find(address);
        if (existing == aps.end() || lastSeen > existing->second.lastSeen) {
            aps.insert_or_assign(address, AccessPoint{std::move(ap), lastSeen});
            associations[address] = &row;
        }
    }
    for (const auto& [address, ap] : aps) {
        clients.erase(address);
        const auto& row = *associations.at(address);
        auto item = info(row, address, ap.lastSeen);
        item.set_kind(v1::AP);
        item.set_bssid(address);
        if (ap.metadata.has_ssid()) item.set_ssid(ap.metadata.ssid());
        if (!ap.metadata.security().empty()) item.set_security(ap.metadata.security());
        if (const auto bytes = unsignedNumber(field(row, "data_bytes"))) {
            sample.ap_data_bytes.emplace(address, *bytes);
        }
        sample.devices.push_back(std::move(item));
    }
    for (auto& [address, item] : clients) {
        const auto ap = associations.find(last_bssids.at(address));
        if (ap != associations.end()) {
            const auto& peers = field(*ap->second, "associated_clients");
            if (peers.is_object()) {
                for (auto peer = peers.begin(); peer != peers.end(); ++peer) {
                    if (mac(Json(peer.key())) == address && string(peer.value(), 96) == item.device_key()) {
                        item.set_related_ap_bssid(ap->first);
                        item.set_association_state(v1::CONFIRMED);
                        break;
                    }
                }
            }
        }
        sample.devices.push_back(std::move(item));
    }
    summary.set_ap_count(static_cast<uint32_t>(aps.size()));
    summary.set_client_count(static_cast<uint32_t>(clients.size()));
    summary.set_truncated(limited);
    summary.set_coverage(limited ? "partial_live_source_window" : "live_source_window");
    summary.set_sampled_at_ms(now);
    std::vector<const AccessPoint*> strongest;
    for (const auto& [_, ap] : aps) strongest.push_back(&ap);
    std::sort(strongest.begin(), strongest.end(), [](const auto* a, const auto* b) {
        const float aSignal = a->metadata.has_rssi_dbm() ? a->metadata.rssi_dbm() : -161.0F;
        const float bSignal = b->metadata.has_rssi_dbm() ? b->metadata.rssi_dbm() : -161.0F;
        if (aSignal != bSignal) return aSignal > bSignal;
        if (a->lastSeen != b->lastSeen) return a->lastSeen > b->lastSeen;
        return a->metadata.bssid() < b->metadata.bssid();
    });
    if (strongest.size() > kPriorityLimit) strongest.resize(kPriorityLimit);
    for (const auto* ap : strongest) *summary.add_priority_aps() = ap->metadata;
    return summary;
}

}  // namespace

LinuxCollector::LinuxCollector(fs::path proc, fs::path sys)
    : proc_(std::move(proc)), sys_(std::move(sys)) {}

v1::SystemMetrics LinuxCollector::sample(Clock::time_point now) {
    v1::SystemMetrics result;
    result.set_sampled_at_ms(unixMillis());
    auto cpu = readCpu(proc_ / "stat");
    if (cpu && previous_cpu_) {
        if (auto delta = deltas(*previous_cpu_, *cpu)) {
            double elapsed = 0;
            for (auto amount : *delta) elapsed += amount;
            if (elapsed > 0) {
                result.set_cpu_usage(static_cast<float>(100 * (1 - ((*delta)[3] + (*delta)[4]) / elapsed)));
            }
        }
    }
    previous_cpu_ = cpu;
    const auto memory = readMemory(proc_ / "meminfo");
    const auto total = memory.find("MemTotal:");
    const auto available = memory.find("MemAvailable:");
    if (total != memory.end()) result.set_memory_total_bytes(total->second);
    if (available != memory.end() && (total == memory.end() || available->second <= total->second)) {
        result.set_memory_available_bytes(available->second);
        if (total != memory.end()) result.set_memory_used_bytes(total->second - available->second);
    }
    if (auto swap = memory.find("SwapTotal:"); swap != memory.end()) result.set_swap_total_bytes(swap->second);
    if (auto swap = memory.find("SwapFree:"); swap != memory.end()
        && (!result.has_swap_total_bytes() || swap->second <= result.swap_total_bytes())) {
        result.set_swap_free_bytes(swap->second);
    }
    if (auto temperature = readTemperature(sys_)) result.set_temperature_c(*temperature);
    if (auto frequency = readFrequency(sys_)) result.set_cpu_frequency_mhz(*frequency);

    // CPU full pressure for the system as a whole is undefined; Linux may display a compatibility zero.
    auto cpuPressure = readPressure(proc_ / "pressure/cpu", false);
    auto memoryPressure = readPressure(proc_ / "pressure/memory", true);
    auto ioPressure = readPressure(proc_ / "pressure/io", true);
    if (cpuPressure.has_some_avg10()) result.set_cpu_psi_some_avg10(cpuPressure.some_avg10());
    if (memoryPressure.has_some_avg10()) result.set_memory_psi_some_avg10(memoryPressure.some_avg10());
    if (cpuPressure.ByteSizeLong() > 0) *result.mutable_cpu_pressure() = std::move(cpuPressure);
    if (memoryPressure.ByteSizeLong() > 0) *result.mutable_memory_pressure() = std::move(memoryPressure);
    if (ioPressure.ByteSizeLong() > 0) *result.mutable_io_pressure() = std::move(ioPressure);

    auto disks = readDisks(proc_ / "diskstats", sys_);
    const auto seconds = std::chrono::duration<double>(now - previous_time_).count();
    if (seconds > 0 && !disks.empty() && disks.size() == previous_disks_.size()) {
        std::array<double, 5> totals{};
        bool continuous = true;
        for (const auto& [key, counters] : disks) {
            auto before = previous_disks_.find(key);
            auto delta = before == previous_disks_.end() ? std::nullopt : deltas(before->second, counters);
            if (!delta) {
                continuous = false;
                break;
            }
            for (size_t i = 0; i < totals.size(); ++i) totals[i] += (*delta)[i];
        }
        if (continuous) {
            // Kernel sector counters independently of device sector size are 512-byte sectors.
            result.set_disk_read_bytes_per_second(totals[1] * 512 / seconds);
            result.set_disk_write_bytes_per_second(totals[3] * 512 / seconds);
            result.set_disk_reads_per_second(totals[0] / seconds);
            result.set_disk_writes_per_second(totals[2] / seconds);
            result.set_disk_busy_ms_per_second(totals[4] / seconds);
        }
    }
    previous_disks_ = std::move(disks);
    previous_time_ = now;
    return result;
}

KismetCollector::KismetCollector(std::string url, std::string api_key, fs::path monitor)
    : url_(std::move(url)), api_key_(std::move(api_key)), monitor_(std::move(monitor)) {
    if (!url_.empty() && url_.back() == '/') url_.pop_back();
}

KismetSample KismetCollector::sample(bool include_devices) {
    KismetSample sample;
    const auto now = unixMillis();
    sample.capture.set_sampled_at_ms(now);
    sample.capture.set_coverage("unavailable");
    sample.wireless.set_coverage("unavailable");
    const auto monitor = readMonitor(monitor_, now);
    sample.capture.set_observation_pause_requested(monitor.pause_requested);
    if (!loopbackUrl(url_) || !validApiKey(api_key_)) {
        sample.capture.set_datasource_state("unconfigured");
        sample.capture.set_reason("kismet_configuration_required");
        previous_packets_.reset();
        return sample;
    }
    const auto status = request(url_, api_key_, "/system/status.json");
    if (status.reachable) sample.capture.set_kismet_running(true);
    if (!status.data.is_object() || string(field(status.data, "kismet.system.version"), 64).empty()) {
        sample.capture.set_datasource_state("degraded");
        sample.capture.set_reason(status.status == 401 || status.status == 403
            ? "kismet_readonly_access_denied" : "kismet_status_unavailable");
        previous_packets_.reset();
        return sample;
    }
    sample.capture.set_datasource_state(monitor.state);
    sample.capture.set_reason(monitor.reason);
    if (monitor.source.empty()) {
        previous_packets_.reset();
        return sample;
    }
    const auto sources = request(url_, api_key_, "/datasource/all_sources.json").data;
    const Json* source = nullptr;
    if (sources.is_array()) {
        for (const auto& entry : sources) {
            if (uuid(field(entry, "kismet.datasource.uuid")) != monitor.source) continue;
            if (source) {
                source = nullptr;
                break;
            }
            source = &entry;
        }
    }
    if (!source || string(field(field(*source, "kismet.datasource.type_driver"), "kismet.datasource.driver.type"), 32) != "linuxwifi") {
        sample.capture.set_datasource_state("degraded");
        sample.capture.set_reason("monitor_datasource_unavailable");
        previous_packets_.reset();
        return sample;
    }
    sample.capture.set_datasource_uuid(monitor.source);
    sample.observation_epoch = monitor.epoch;
    sample.capture_profile = monitor.profile;
    sample.kismet_started = unsignedNumber(field(status.data, "kismet.system.timestamp.start_sec"));
    const auto running = flag(field(*source, "kismet.datasource.running"));
    const auto paused = flag(field(*source, "kismet.datasource.paused"));
    const auto error = flag(field(*source, "kismet.datasource.error"));
    if (running) sample.capture.set_datasource_running(*running);
    if (paused) sample.capture.set_datasource_paused(*paused);
    if (error) sample.capture.set_datasource_error(*error);
    if (running != true || paused != false || error != false) {
        sample.capture.set_datasource_state("degraded");
        sample.capture.set_reason("monitor_datasource_not_running");
        previous_packets_.reset();
        return sample;
    }
    sample.capture.set_current_channel(string(field(*source, "kismet.datasource.channel"), 24));
    sample.capture.set_coverage("live_monitor_active");
    auto rate = recentRate(field(*source, "kismet.datasource.packets_rrd"), now);
    const auto dropped = unsignedNumber(field(*source, "kismet.datasource.num_dropped_packets"));
    const auto packets = unsignedNumber(field(*source, "kismet.datasource.num_packets"));
    const auto measured = Clock::now();
    const auto elapsed = std::chrono::duration<double>(measured - previous_time_).count();
    if (rate) sample.capture.set_packets_per_second(*rate);
    if (dropped) sample.capture.set_dropped_packets(*dropped);
    if (packets && previous_packets_ && monitor.source == previous_uuid_ && *packets >= *previous_packets_
        && elapsed >= 1 && elapsed <= 60) {
        auto delta = static_cast<double>(*packets - *previous_packets_) / elapsed;
        if (delta < static_cast<double>(std::numeric_limits<uint64_t>::max())) {
            sample.capture.set_processed_packets_per_second(static_cast<uint64_t>(delta));
        }
    }
    previous_uuid_ = monitor.source;
    previous_packets_ = packets;
    previous_time_ = measured;
    if (sample.capture.has_packets_per_second() || sample.capture.has_processed_packets_per_second()
        || sample.capture.has_dropped_packets()) {
        sample.capture.set_packet_statistics_source("kismet_datasource");
    }

    // Packet chain data are instance-wide. Use backlog only when that scope equals the live monitor.
    if (sources.size() == 1) {
        auto packetStats = request(url_, api_key_, "/packetchain/packet_stats.json",
                                   {{"fields", Json::array({"kismet.packetchain.queued_packets_rrd"})}}).data;
        const auto backlog = recentRate(field(packetStats, "kismet.packetchain.queued_packets_rrd"), now);
        if (backlog) {
            sample.capture.set_backlog(*backlog);
            sample.capture.set_packet_statistics_source("kismet_datasource_and_single_source_packet_chain");
        }
    }
    if (!include_devices) {
        sample.wireless.set_coverage("resource_fallback");
        return sample;
    }
    std::string upper = monitor.source;
    for (auto& ch : upper) if (ch >= 'a' && ch <= 'f') ch -= 'a' - 'A';
    const auto view = readDeviceWindow(url_, api_key_, "/devices/views/seenby-" + upper + "/devices.json",
                                      monitor.source, now);
    sample.wireless = summarize(view, now, sample);
    if (sample.wireless.has_ap_count()) {
        sample.capture.set_tracked_devices(uint64_t(sample.wireless.ap_count()) + sample.wireless.client_count());
    }
    return sample;
}

KismetAlerts KismetCollector::sample_alerts() const {
    KismetAlerts output;
    if (!loopbackUrl(url_) || !validApiKey(api_key_)) return output;
    const auto reply = request(url_, api_key_, "/alerts/all_alerts.json");
    if (!reply.data.is_array() || reply.data.size() > 1024) return output;
    output.reachable = true;
    const auto now = unixMillis();
    for (const auto& row : reply.data) {
        const auto timestamp = secondsMillis(field(row, "kismet.alert.timestamp"), now);
        const auto name = string(field(row, "kismet.alert.header"), 64);
        if (timestamp == 0 || timestamp > now || now - timestamp > 300000 || name.empty()) continue;
        const auto description = string(field(row, "kismet.alert.text"), 384);
        const auto bssid = mac(field(row, "kismet.alert.bssid"));
        const auto source_mac = mac(field(row, "kismet.alert.source_mac"));
        const auto transmitter = mac(field(row, "kismet.alert.transmitter_mac"));
        const auto receiver = mac(field(row, "kismet.alert.dest_mac"));
        const auto severity = unsignedNumber(field(row, "kismet.alert.severity")).value_or(0);
        const auto key = Json::array({name, timestamp, bssid, source_mac, transmitter, receiver, description}).dump();
        unsigned char digest[SHA256_DIGEST_LENGTH]{};
        SHA256(reinterpret_cast<const unsigned char*>(key.data()), key.size(), digest);
        std::string id = "kismet:";
        constexpr char hex[] = "0123456789abcdef";
        for (auto byte : digest) {
            id.push_back(hex[byte >> 4]);
            id.push_back(hex[byte & 15]);
        }
        v1::MonitoringEvent event;
        event.set_event_id(id);
        event.set_evidence_id(id.substr(7, 24));
        event.set_timestamp_ms(timestamp);
        event.set_observed_at_ms(timestamp);
        event.set_event_type("kismet_alert:" + name);
        event.set_source("Kismet");
        event.set_source_scope("kismet_instance");
        event.set_event_category(v1::SECURITY);
        if (!bssid.empty()) event.set_bssid(bssid);
        event.set_description(description.empty() ? name : description);
        // Rule set v1: native, high-severity management-frame alerts with a specific BSS and text.
        const bool selected = name == "DEAUTHFLOOD" || name == "BCASTDISCON" ||
                              name == "DOT11CSAFLOOD" || name == "DOT11CSASPOOF";
        const bool supported = selected && severity >= 15 && !bssid.empty() && !description.empty();
        // One upstream WIDS alert is a useful risk signal, not independently
        // corroborated proof of an attack, even at Kismet severity 20.
        event.set_confidence(v1::LIMITED);
        event.set_risk_class(supported ? (severity >= 20 ? v1::CRITICAL : v1::HIGH) : v1::SUSPICIOUS);
        event.set_summary(supported ? "疑似高危无线行为" : "Kismet 无线异常观测");
        event.set_priority(severity >= 20 ? v1::P0 : (severity >= 15 ? v1::P1 : v1::P2));
        event.set_occurrences(1);
        output.events.push_back(std::move(event));
    }
    return output;
}

}  // namespace pocketnet::telemetry
