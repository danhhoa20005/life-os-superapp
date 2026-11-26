#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <new>
#include <vector>

#if defined(__GNUC__) || defined(__clang__)
#define LIFEOS_FFI_EXPORT extern "C" __attribute__((visibility("default"))) __attribute__((used))
#else
#define LIFEOS_FFI_EXPORT extern "C" __declspec(dllexport)
#endif

namespace {

struct LftqModel {
  uint32_t num_classes = 0;
  uint32_t dim = 0;
  uint32_t num_buckets = 0;
  float temperature = 1.0f;
  bool is_diagonal_w = false;
  std::vector<float> scales_a;
  std::vector<int8_t> weights_a;
  std::vector<float> weights_w;
  std::vector<float> bias_b;
};

uint16_t read_u16_le(const uint8_t* p) {
  return static_cast<uint16_t>(p[0]) | (static_cast<uint16_t>(p[1]) << 8);
}

uint32_t read_u32_le(const uint8_t* p) {
  return static_cast<uint32_t>(p[0]) |
         (static_cast<uint32_t>(p[1]) << 8) |
         (static_cast<uint32_t>(p[2]) << 16) |
         (static_cast<uint32_t>(p[3]) << 24);
}

float read_f32_le(const uint8_t* p) {
  uint32_t bits = read_u32_le(p);
  float val = 0.0f;
  std::memcpy(&val, &bits, sizeof(float));
  return val;
}

}  // namespace

LIFEOS_FFI_EXPORT uint8_t* lifeos_ftx_alloc(int32_t byte_len) {
  if (byte_len <= 0) return nullptr;
  return static_cast<uint8_t*>(std::malloc(static_cast<size_t>(byte_len)));
}

LIFEOS_FFI_EXPORT void lifeos_ftx_dealloc(void* ptr) {
  if (ptr != nullptr) {
    std::free(ptr);
  }
}

LIFEOS_FFI_EXPORT int32_t lifeos_ftx_abi_version() {
  return 100;
}

LIFEOS_FFI_EXPORT void* lifeos_ftx_create(const uint8_t* data, int32_t byte_len) {
  if (data == nullptr || byte_len < 32) {
    return nullptr;
  }
  // Verify "LFTQ" magic header & version == 1
  if (data[0] != 'L' || data[1] != 'F' || data[2] != 'T' || data[3] != 'Q') {
    return nullptr;
  }
  const uint32_t version = read_u32_le(data + 4);
  if (version != 1) {
    return nullptr;
  }

  const uint32_t k = read_u32_le(data + 8);
  const uint32_t dim = read_u32_le(data + 12);
  const uint32_t buckets = read_u32_le(data + 16);
  const float temp = read_f32_le(data + 28);

  if (k == 0 || k > 512 || dim == 0 || dim > 512 || buckets == 0 || buckets > 262144) {
    return nullptr;
  }

  size_t offset = 32;
  const size_t total = static_cast<size_t>(byte_len);

  // Skip UTF-8 label table safely with strict bounds checks
  for (uint32_t i = 0; i < k; ++i) {
    if (offset + 2 > total) return nullptr;
    const uint16_t str_len = read_u16_le(data + offset);
    offset += 2;
    if (offset + str_len > total) return nullptr;
    offset += str_len;
  }

  const size_t scales_bytes = static_cast<size_t>(buckets) * sizeof(float);
  const size_t qa_bytes = static_cast<size_t>(buckets) * static_cast<size_t>(dim);
  const size_t w_bytes = static_cast<size_t>(k) * static_cast<size_t>(dim) * sizeof(float);
  const size_t b_bytes = static_cast<size_t>(k) * sizeof(float);

  if (offset + scales_bytes + qa_bytes + w_bytes + b_bytes > total) {
    return nullptr;
  }

  auto* model = new (std::nothrow) LftqModel();
  if (model == nullptr) return nullptr;

  model->num_classes = k;
  model->dim = dim;
  model->num_buckets = buckets;
  model->temperature = (temp > 1e-4f) ? temp : 1.0f;

  model->scales_a.resize(buckets);
  for (uint32_t i = 0; i < buckets; ++i) {
    model->scales_a[i] = read_f32_le(data + offset + i * 4);
  }
  offset += scales_bytes;

  model->weights_a.resize(qa_bytes);
  std::memcpy(model->weights_a.data(), data + offset, qa_bytes);
  offset += qa_bytes;

  const size_t w_count = static_cast<size_t>(k) * static_cast<size_t>(dim);
  model->weights_w.resize(w_count);
  for (size_t i = 0; i < w_count; ++i) {
    model->weights_w[i] = read_f32_le(data + offset + i * 4);
  }
  offset += w_bytes;

  model->bias_b.resize(k);
  for (uint32_t i = 0; i < k; ++i) {
    model->bias_b[i] = read_f32_le(data + offset + i * 4);
  }

  bool is_diag = (k == dim);
  if (is_diag) {
    for (uint32_t r = 0; r < k && is_diag; ++r) {
      const size_t r_base = static_cast<size_t>(r) * dim;
      for (uint32_t c = 0; c < dim; ++c) {
        if (r != c && model->weights_w[r_base + c] != 0.0f) {
          is_diag = false;
          break;
        }
      }
    }
  }
  model->is_diagonal_w = is_diag;

  return model;
}

LIFEOS_FFI_EXPORT int32_t lifeos_ftx_predict(
    void* handle,
    const uint32_t* bucket_ids,
    int32_t bucket_count,
    float* out_probs,
    int32_t out_len) {
  if (handle == nullptr || out_probs == nullptr) {
    return -1;
  }
  const auto* m = static_cast<const LftqModel*>(handle);
  if (static_cast<uint32_t>(out_len) < m->num_classes) {
    return -2;
  }

  const uint32_t k = m->num_classes;
  const uint32_t dim = m->dim;

  if (bucket_ids == nullptr || bucket_count <= 0) {
    const float u = 1.0f / static_cast<float>(k);
    for (uint32_t c = 0; c < k; ++c) {
      out_probs[c] = u;
    }
    return 0;
  }

  float h[512] = {0.0f};
  int32_t valid_count = 0;
  for (int32_t i = 0; i < bucket_count; ++i) {
    const uint32_t b_id = bucket_ids[i] % m->num_buckets;
    const float sc = m->scales_a[b_id];
    valid_count++;
    if (sc == 0.0f) continue;
    const int8_t* row = m->weights_a.data() + (static_cast<size_t>(b_id) * dim);
    for (uint32_t d = 0; d < dim; ++d) {
      h[d] += static_cast<float>(row[d]) * sc;
    }
  }

  const float inv_n = 1.0f / static_cast<float>(std::max(valid_count, 1));
  for (uint32_t d = 0; d < dim; ++d) {
    h[d] *= inv_n;
  }

  const float inv_temp = 1.0f / m->temperature;
  float max_logit = -1e30f;
  if (m->is_diagonal_w) {
    for (uint32_t c = 0; c < k; ++c) {
      const float sum =
          m->bias_b[c] + m->weights_w[static_cast<size_t>(c) * dim + c] * h[c];
      const float scaled = sum * inv_temp;
      out_probs[c] = scaled;
      if (scaled > max_logit) {
        max_logit = scaled;
      }
    }
  } else {
    for (uint32_t c = 0; c < k; ++c) {
      const float* w_row = m->weights_w.data() + (static_cast<size_t>(c) * dim);
      float sum = m->bias_b[c];
      for (uint32_t d = 0; d < dim; ++d) {
        sum += w_row[d] * h[d];
      }
      const float scaled = sum * inv_temp;
      out_probs[c] = scaled;
      if (scaled > max_logit) {
        max_logit = scaled;
      }
    }
  }

  float exp_sum = 0.0f;
  for (uint32_t c = 0; c < k; ++c) {
    const float e = std::exp(out_probs[c] - max_logit);
    out_probs[c] = e;
    exp_sum += e;
  }

  const float inv_sum = (exp_sum > 0.0f) ? (1.0f / exp_sum) : (1.0f / static_cast<float>(k));
  for (uint32_t c = 0; c < k; ++c) {
    out_probs[c] *= inv_sum;
  }
  return 0;
}

LIFEOS_FFI_EXPORT void lifeos_ftx_destroy(void* handle) {
  if (handle != nullptr) {
    delete static_cast<LftqModel*>(handle);
  }
}
