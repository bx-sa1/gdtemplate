SDK_VERSION := prerelease
ifeq (,$(wildcard sdk/build/contract.json))
	CONTRACT := --prev=sdk/build/contract.json
endif

sdk/build/sdk-${SDK_VERSION}:
	godot --headless --path . --script res://sdk/build_sdk.gd -- --version=${SDK_VERSION} ${CONTRACT}
