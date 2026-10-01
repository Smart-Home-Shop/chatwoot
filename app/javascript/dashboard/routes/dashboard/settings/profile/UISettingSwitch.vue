<script setup>
import { computed, useId } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';

const props = defineProps({
  // Key in the agent's UI settings this switch turns on/off
  settingKey: {
    type: String,
    required: true,
  },
  label: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
});

const switchId = useId();
const descriptionId = useId();

const { uiSettings, updateUISettings } = useUISettings();

const isEnabled = computed({
  get: () => !!uiSettings.value[props.settingKey],
  set: value => updateUISettings({ [props.settingKey]: value }),
});
</script>

<template>
  <div class="flex gap-2 justify-between w-full items-start">
    <div>
      <label
        :for="switchId"
        class="text-n-gray-12 font-medium leading-6 text-sm cursor-pointer"
      >
        {{ label }}
      </label>
      <p :id="descriptionId" class="text-n-gray-11">
        {{ description }}
      </p>
    </div>
    <ToggleSwitch
      :id="switchId"
      v-model="isEnabled"
      :aria-describedby="descriptionId"
      class="mt-1"
    />
  </div>
</template>
