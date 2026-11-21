#include <condition_variable>
#include <iostream>
#include <mutex>
#include <optional>
#include <queue>
#include <thread>
#include <vector>

class Queue {
public:
    bool push(int value) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (closed_) {
                return false;
            }
            values_.push(value);
        }
        ready_.notify_one();
        return true;
    }

    std::optional<int> pop() {
        std::unique_lock<std::mutex> lock(mutex_);
        ready_.wait(lock, [this] { return closed_ || !values_.empty(); });
        if (values_.empty()) {
            return std::nullopt;
        }
        const auto value = values_.front();
        values_.pop();
        return value;
    }

    void close() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            closed_ = true;
        }
        ready_.notify_all();
    }

private:
    std::mutex mutex_;
    std::condition_variable ready_;
    std::queue<int> values_;
    bool closed_ = false;
};

int main() {
    Queue queue;
    std::vector<int> received;
    std::thread consumer([&] {
        while (const auto value = queue.pop()) {
            received.push_back(*value);
        }
    });
    std::thread producer([&] {
        for (int n = 0; n < 100; ++n) {
            queue.push(n);
        }
        queue.close();
    });
    producer.join();
    consumer.join();

    if (received.size() != 100 || queue.push(100) || queue.pop()) {
        std::cerr << "queue contents or closed state was incorrect\n";
        return 1;
    }
    for (int n = 0; n < 100; ++n) {
        if (received[n] != n) {
            std::cerr << "FIFO order was incorrect\n";
            return 1;
        }
    }

    Queue empty;
    bool stopped = false;
    std::thread waiting([&] { stopped = !empty.pop(); });
    empty.close();
    waiting.join();
    return stopped ? 0 : 1;
}
