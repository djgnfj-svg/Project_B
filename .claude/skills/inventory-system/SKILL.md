---
name: inventory-system
description: 인벤토리 시스템을 만들 때 사용 — Resource 기반 아이템, 슬롯 관리, 스택, UI 바인딩
---

# Godot 4.3+의 인벤토리 시스템

모든 예제는 폐기된 API 없이 Godot 4.3+를 대상으로 한다. GDScript를 먼저, 그다음 C#을 보여준다.

> **관련 스킬:** 커스텀 Resource 데이터 컨테이너는 **resource-pattern**, 인벤토리 직렬화는 **save-load**, 인벤토리 변경 알림은 **event-bus**, 인벤토리 UI 표시는 **hud-system**을 보라.

---

## 1. 아키텍처 개요

```
┌─────────────────────────────────────────────────────────┐
│                        UI Layer                         │
│   InventoryUI (Control)                                 │
│     └─ GridContainer                                    │
│           └─ SlotUI × N (Button)                        │
│                 └─ TextureRect (icon) + Label (qty)     │
│                                                         │
│   Connects to: inventory_changed signal                 │
│   Drag-and-drop via _get_drag_data / _drop_data         │
└───────────────────────┬─────────────────────────────────┘
                        │ reads / mutates
┌───────────────────────▼─────────────────────────────────┐
│                    Inventory (Node)                      │
│   slots: Array[InventorySlot]                           │
│   add_item(item, qty) → leftover: int                   │
│   remove_item(item, qty)                                │
│   has_item(item, qty) → bool                            │
│   get_item_count(item) → int                            │
│                                                         │
│   signals: inventory_changed                            │
│             item_added(item, quantity)                  │
│             item_removed(item, quantity)                │
└───────────────────────┬─────────────────────────────────┘
                        │ references
┌───────────────────────▼─────────────────────────────────┐
│                   Data Layer (Resources)                 │
│   ItemData (Resource)                                   │
│     id, name, description, icon, max_stack_size,        │
│     item_type enum                                      │
│                                                         │
│   InventorySlot (inner class / Resource)                │
│     item: ItemData, quantity: int                       │
└─────────────────────────────────────────────────────────┘
```

---

## 2. ItemData Resource

아이템을 Resource로 정의해 `.tres` 파일에 살고, 씬 간에 공유 가능하며, 완전한 에디터 통합의 이점을 얻게 하라.

### GDScript

```gdscript
# item_data.gd
class_name ItemData
extends Resource

enum ItemType {
    CONSUMABLE,
    EQUIPMENT,
    MATERIAL,
    KEY_ITEM,
}

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export var max_stack_size: int = 99
@export var item_type: ItemType = ItemType.MATERIAL
```

아이템 에셋 생성: **res://items/potion_health.tres**, `id = "potion_health"` 등 설정.

### C#

```csharp
// ItemData.cs
using Godot;

[GlobalClass]
public partial class ItemData : Resource
{
    public enum ItemType
    {
        Consumable,
        Equipment,
        Material,
        KeyItem,
    }

    [Export] public string Id          { get; set; } = "";
    [Export] public string Name        { get; set; } = "";
    [Export] public string Description { get; set; } = "";
    [Export] public Texture2D Icon     { get; set; }
    [Export] public int MaxStackSize   { get; set; } = 99;
    [Export] public ItemType Type      { get; set; } = ItemType.Material;
}
```

> `.tres` 파일을 만들 때 인스펙터 드롭다운이 `ItemData`를 리소스 타입으로 표시하도록 `[GlobalClass]`를 써라.

---

## 3. Inventory 클래스

### GDScript

```gdscript
# inventory.gd
class_name Inventory
extends Node

signal inventory_changed
signal item_added(item: ItemData, quantity: int)
signal item_removed(item: ItemData, quantity: int)

@export var capacity: int = 20

var slots: Array[InventorySlot] = []


func _ready() -> void:
    slots.resize(capacity)
    for i in capacity:
        slots[i] = InventorySlot.new()


# Returns the number of items that could NOT be added (leftover).
func add_item(item: ItemData, quantity: int = 1) -> int:
    var remaining := quantity

    # Fill existing stacks first
    for slot in slots:
        if remaining <= 0:
            break
        if not slot.is_empty() and slot.item == item:
            remaining = slot.add_to_stack(remaining)

    # Open empty slots next
    for slot in slots:
        if remaining <= 0:
            break
        if slot.is_empty():
            slot.item = item
            remaining = slot.add_to_stack(remaining)

    var added := quantity - remaining
    if added > 0:
        item_added.emit(item, added)
        inventory_changed.emit()

    return remaining


func remove_item(item: ItemData, quantity: int = 1) -> void:
    var remaining := quantity

    for slot in slots:
        if remaining <= 0:
            break
        if not slot.is_empty() and slot.item == item:
            var removed := mini(slot.quantity, remaining)
            slot.remove_from_stack(removed)
            remaining -= removed

    var actually_removed := quantity - remaining
    if actually_removed > 0:
        item_removed.emit(item, actually_removed)
        inventory_changed.emit()


func has_item(item: ItemData, quantity: int = 1) -> bool:
    return get_item_count(item) >= quantity


func get_item_count(item: ItemData) -> int:
    var total := 0
    for slot in slots:
        if not slot.is_empty() and slot.item == item:
            total += slot.quantity
    return total
```

### C#

```csharp
// Inventory.cs
using Godot;
using Godot.Collections;

public partial class Inventory : Node
{
    [Signal] public delegate void InventoryChangedEventHandler();
    [Signal] public delegate void ItemAddedEventHandler(ItemData item, int quantity);
    [Signal] public delegate void ItemRemovedEventHandler(ItemData item, int quantity);

    [Export] public int Capacity { get; set; } = 20;

    public Array<InventorySlot> Slots { get; private set; } = new();

    public override void _Ready()
    {
        for (int i = 0; i < Capacity; i++)
            Slots.Add(new InventorySlot());
    }

    /// <summary>Returns the number of items that could NOT be added (leftover).</summary>
    public int AddItem(ItemData item, int quantity = 1)
    {
        int remaining = quantity;

        // Fill existing stacks first
        foreach (var slot in Slots)
        {
            if (remaining <= 0) break;
            if (!slot.IsEmpty() && slot.Item == item)
                remaining = slot.AddToStack(remaining);
        }

        // Open empty slots next
        foreach (var slot in Slots)
        {
            if (remaining <= 0) break;
            if (slot.IsEmpty())
            {
                slot.Item = item;
                remaining = slot.AddToStack(remaining);
            }
        }

        int added = quantity - remaining;
        if (added > 0)
        {
            EmitSignal(SignalName.ItemAdded, item, added);
            EmitSignal(SignalName.InventoryChanged);
        }

        return remaining;
    }

    public void RemoveItem(ItemData item, int quantity = 1)
    {
        int remaining = quantity;

        foreach (var slot in Slots)
        {
            if (remaining <= 0) break;
            if (!slot.IsEmpty() && slot.Item == item)
            {
                int removed = Mathf.Min(slot.Quantity, remaining);
                slot.RemoveFromStack(removed);
                remaining -= removed;
            }
        }

        int actuallyRemoved = quantity - remaining;
        if (actuallyRemoved > 0)
        {
            EmitSignal(SignalName.ItemRemoved, item, actuallyRemoved);
            EmitSignal(SignalName.InventoryChanged);
        }
    }

    public bool HasItem(ItemData item, int quantity = 1)
        => GetItemCount(item) >= quantity;

    public int GetItemCount(ItemData item)
    {
        int total = 0;
        foreach (var slot in Slots)
            if (!slot.IsEmpty() && slot.Item == item)
                total += slot.Quantity;
        return total;
    }
}
```

---

## 4. InventorySlot

`InventorySlot`은 아이템 참조와 수량을 추적하는 경량 객체다. `Inventory`의 내부 클래스(GDScript)나 독립 `RefCounted` 서브클래스(C#)로 정의하라.

### GDScript

```gdscript
# inventory_slot.gd  — or nest as inner class inside inventory.gd
class_name InventorySlot
extends RefCounted

var item: ItemData = null
var quantity: int   = 0


func is_empty() -> bool:
    return item == null or quantity <= 0


func can_stack(new_item: ItemData) -> bool:
    return not is_empty() and item == new_item and quantity < item.max_stack_size


# Adds amount to this slot, capped at max_stack_size.
# Returns the leftover that did not fit.
func add_to_stack(amount: int) -> int:
    if item == null:
        push_error("InventorySlot.add_to_stack: slot has no item assigned")
        return amount
    var space    := item.max_stack_size - quantity
    var to_add   := mini(amount, space)
    quantity     += to_add
    return amount - to_add


# Removes amount from this slot. Clears the slot when quantity reaches zero.
func remove_from_stack(amount: int) -> void:
    quantity -= amount
    if quantity <= 0:
        quantity = 0
        item     = null
```

### C#

```csharp
// InventorySlot.cs
using Godot;

public partial class InventorySlot : RefCounted
{
    public ItemData Item     { get; set; }
    public int      Quantity { get; set; }

    public bool IsEmpty() => Item == null || Quantity <= 0;

    public bool CanStack(ItemData newItem)
        => !IsEmpty() && Item == newItem && Quantity < Item.MaxStackSize;

    /// <summary>Adds amount to this slot. Returns leftover that did not fit.</summary>
    public int AddToStack(int amount)
    {
        if (Item == null)
        {
            GD.PushError("InventorySlot.AddToStack: slot has no item assigned");
            return amount;
        }
        int space  = Item.MaxStackSize - Quantity;
        int toAdd  = Mathf.Min(amount, space);
        Quantity  += toAdd;
        return amount - toAdd;
    }

    /// <summary>Removes amount from this slot. Clears when quantity reaches zero.</summary>
    public void RemoveFromStack(int amount)
    {
        Quantity -= amount;
        if (Quantity <= 0)
        {
            Quantity = 0;
            Item     = null;
        }
    }
}
```

---

## 8. 구현 체크리스트

- [ ] `ItemData`가 `Resource`를 상속하고 인스펙터에서 설정된 안정적인 `id` 문자열을 가진다
- [ ] `ItemData` 파일이 `res://items/` 아래에 살며 버전 관리에 커밋된다
- [ ] `Inventory.add_item()`이 남은 개수를 반환한다; 호출자가 가득 찬 인벤토리를 처리한다
- [ ] `inventory_changed` 시그널이 모든 UI 갱신을 구동한다 — UI가 프레임마다 폴링하지 않는다
- [ ] `InventorySlot.remove_from_stack()`이 수량이 0이 되면 `item`을 `null`로 지운다
- [ ] 장비 슬롯이 문자열이 아니라 `SlotType` enum으로 키됨 — 컴파일 타임에 오타를 잡으려고
- [ ] `Equipment.get_total_stat()`이 스탯이 필요할 때 호출됨 — 프로파일링이 요구하지 않는 한 캐시하지 않음
- [ ] 직렬화가 `id + quantity`만 저장함 — 전체 `ItemData` 객체나 리소스 경로는 절대 아님
- [ ] `ItemRegistry`가 시작 시 아이템을 로드함; 모든 역직렬화가 그것을 거침
- [ ] 드래그앤드롭이 슬롯 내용을 직접 교환한 뒤 `inventory_changed`를 한 번 발신함
- [ ] 스택을 막으려고 `EQUIPMENT`와 `KEY_ITEM` 타입에 `max_stack_size = 1`
- [ ] 모든 `push_error()` 메시지가 추적하기 쉽도록 클래스명과 메서드를 포함함

## 5. 장비 확장

타입 지정 슬롯 맵으로 `Inventory` 클래스를 확장해 장비 슬롯(`HEAD`, `CHEST`, `WEAPON` 등)을 추가하라. 스탯 집계는 장착 아이템 전체의 `ItemData.stats`를 합산해 돌아간다. 슬롯이 바뀌면 `equipment_changed`를 발신한다.

---

## 6. UI 바인딩

슬롯 그리드 UI: `Panel` 슬롯 위젯의 `GridContainer`로, 각각 하나의 `InventorySlot`을 렌더한다. 드래그앤드롭은 슬롯 위젯의 `_get_drag_data` / `_drop_data` / `_can_drop_data`를 쓴다. Inventory가 `inventory_changed`를 발신하고, UI가 영향받은 슬롯을 다시 렌더한다.

---

## 7. 직렬화

Inventory + Equipment를 아이템 리소스 경로로 키된 Dictionary로 영속화하라(ItemData가 `res://items/<name>.tres`에 살기 때문). `load(path)`로 다시 로드하고 슬롯 리스트를 재구성한다. version 필드가 로드 시 마이그레이션을 통제한다.

---
