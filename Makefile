.PHONY: start apply deploy open-argocd get-password

start:
	minikube start

apply:
	kubectl apply -f application.yaml

deploy: start apply

open-argocd:
	@echo "Mở ArgoCD tại địa chỉ: https://localhost:8080 (username mặc định: admin)"
	kubectl port-forward svc/argocd-server -n argocd 8080:443

get-password:
	@echo "Mật khẩu Admin đã được mã hóa base64:"
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
	@echo ""
