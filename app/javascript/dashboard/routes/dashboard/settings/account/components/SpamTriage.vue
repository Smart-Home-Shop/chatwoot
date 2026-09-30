<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();
const isEnabled = ref(false);

const { currentAccount, updateAccount } = useAccount();

watch(
  currentAccount,
  () => {
    const { spam_triage } = currentAccount.value?.settings || {};
    isEnabled.value = !!spam_triage;
  },
  { deep: true, immediate: true }
);

const updateAccountSettings = async settings => {
  try {
    await updateAccount(settings);
    useAlert(t('GENERAL_SETTINGS.FORM.SPAM_TRIAGE.API.SUCCESS'));
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.FORM.SPAM_TRIAGE.API.ERROR'));
  }
};

const toggleSpamTriage = async () => {
  return updateAccountSettings({
    spam_triage: isEnabled.value,
  });
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.SPAM_TRIAGE.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.SPAM_TRIAGE.NOTE')"
    with-border
  >
    <template #headerActions>
      <div class="flex justify-end">
        <Switch v-model="isEnabled" @change="toggleSpamTriage" />
      </div>
    </template>
  </SectionLayout>
</template>
