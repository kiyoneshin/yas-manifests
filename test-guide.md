# Hướng dẫn Kiểm thử Service Mesh (Istio)

Tài liệu này hướng dẫn cách kiểm thử các thiết lập Service Mesh (Istio) bao gồm chính sách bảo mật **AuthorizationPolicy** (Zero-Trust) và chính sách tự động gọi lại **Retry Policy** (VirtualService).

---

## 1. Kịch bản 1: Kiểm thử chính sách bảo mật (Authorization Policy)

Thiết lập bảo mật: **Chỉ cho phép duy nhất service `storefront-bff` gọi vào service `cart`. Các dịch vụ khác (ví dụ `product`) sẽ bị chặn hoàn toàn.**

### Kịch bản 1a: Cho phép kết nối (Từ storefront-bff sang cart)
* **Kết quả mong đợi:** Trả về mã **`404 Not Found`** (Kết nối đi xuyên qua proxy thành công tới service `cart`, lỗi 404 chỉ là do `cart` không cấu hình trang web ở đường dẫn gốc `/`).
* **Lệnh chạy:**
  ```powershell
  $POD=$(kubectl get pod -l app=storefront-bff -n dev -o jsonpath="{.items[0].metadata.name}"); kubectl exec -it $POD -n dev -c storefront-bff -- wget --spider -S http://cart:8081/
  ```

### Kịch bản 1b: Bị chặn kết nối (Từ product sang cart)
* **Kết quả mong đợi:** Trả về mã **`403 Forbidden`** (Bị Istio Envoy Proxy chặn đứng ngay tại cửa ngõ vì không có quyền truy cập).
* **Lệnh chạy:**
  ```powershell
  $POD=$(kubectl get pod -l app=product -n dev -o jsonpath="{.items[0].metadata.name}"); kubectl exec -it $POD -n dev -c product -- wget --spider -S http://cart:8081/
  ```

---

## 2. Kịch bản 2: Kiểm thử cơ chế tự động gọi lại (Retry Policy)

Thiết lập bảo mật: **Nếu kết nối tới `cart` bị lỗi sập mạng hoặc trả về lỗi 5xx, Envoy Proxy sẽ tự động gọi lại (retry) ngầm tối đa 3 lần trước khi trả lỗi về ứng dụng.**

Để kiểm thử, chúng ta sẽ giả lập sự cố bằng cách hạ số lượng pod của `cart` về `0` (sập mạng hoàn toàn), sau đó thực hiện lệnh gọi từ `storefront-bff` và lọc log để đếm số lần retry của Envoy.

### Các bước thực hiện chi tiết:

#### **Bước 1: Hạ số lượng pod của `cart` về 0 để giả lập sập dịch vụ**
Chạy lệnh này trên cửa sổ Terminal chính để tắt dịch vụ `cart`:
```bash
kubectl scale deployment cart -n dev --replicas=0
```

#### **Bước 2: Thực hiện lệnh gọi từ `storefront-bff` sang `cart`**
Chạy lệnh này để gửi request lỗi đến `cart` (kích hoạt cơ chế gọi lại):
```powershell
$POD=$(kubectl get pod -l app=storefront-bff -n dev -o jsonpath="{.items[0].metadata.name}"); kubectl exec -it $POD -n dev -c storefront-bff -- wget --spider -S http://cart:8081/
```
*(Lệnh này sẽ chạy mất khoảng vài giây và trả về lỗi `503 Service Unavailable` do Envoy phải thực hiện các lượt gọi lại liên tiếp).*

#### **Bước 3: Kiểm tra log của Envoy Proxy để xem số lần gọi lại**
Để tránh việc các dòng log Health Check (`/healthz/ready`) tự động của Kubernetes làm trôi mất màn hình, hãy chạy lệnh lọc log tĩnh (sau khi chạy lệnh wget ở Bước 2) thay vì sử dụng logs follow (`-f`):

* **Trên Windows PowerShell:**
  ```powershell
  $POD=$(kubectl get pod -l app=storefront-bff -n dev -o jsonpath="{.items[0].metadata.name}"); kubectl logs $POD -c istio-proxy -n dev --tail=150 | Select-String "performing retry"
  ```
* **Trên Linux / macOS / Git Bash:**
  ```bash
  POD=$(kubectl get pod -l app=storefront-bff -n dev -o jsonpath="{.items[0].metadata.name}"); kubectl logs $POD -c istio-proxy -n dev --tail=150 | grep "performing retry"
  ```

* **Kết quả mong đợi:** Xuất hiện đúng **3 dòng log** chứa thông báo `performing retry` như sau:
  ```text
  2026-07-09T04:57:56.275184Z  debug  envoy router ... performing retry ...
  2026-07-09T04:57:56.388367Z  debug  envoy router ... performing retry ...
  2026-07-09T04:57:56.449509Z  debug  envoy router ... performing retry ...
  ```
  *(Điều này chứng minh Envoy đã gọi lại ngầm 3 lần trước khi chịu đầu hàng và báo lỗi 503).*

#### **Bước 4: Khôi phục lại dịch vụ `cart`**
Chạy lệnh này để phục hồi số lượng pod của `cart` về trạng thái hoạt động bình thường:
```bash
kubectl scale deployment cart -n dev --replicas=1
```
