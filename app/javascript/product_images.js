export function initProductImages() {
  // Support both product-images and variant-images containers
  const addImageBtn = document.getElementById('add-image-btn');
  const productImagesContainer = document.getElementById('product-images') || document.getElementById('variant-images');
  
  if (!addImageBtn || !productImagesContainer) {
    return;
  }
  
  let variantOptions = [];
  let imageIndex = 0;
  
  // Get variant options from JSON script tag
  try {
    const configScript = document.getElementById('product-images-config');
    if (configScript) {
      const jsonText = configScript.textContent || configScript.innerText || '[]';
      console.log('JSON text:', jsonText);
      variantOptions = JSON.parse(jsonText);
      console.log('Parsed variant options:', variantOptions);
    } else {
      console.warn('product-images-config script tag not found');
    }
  } catch (e) {
    console.error('Error parsing variant options:', e);
    console.error('JSON text was:', document.getElementById('product-images-config')?.textContent);
    variantOptions = [];
  }
  
  // Get image index from data attribute
  try {
    imageIndex = parseInt(productImagesContainer.dataset.imageIndex || '0', 10);
  } catch (e) {
    console.error('Error parsing image index:', e);
    imageIndex = 0;
  }

  function createVariantSelectOptions() {
    return variantOptions.map(function(option) {
      return '<option value="' + (option[1] || '') + '">' + option[0] + '</option>';
    }).join('');
  }

  function createNewImageField() {
    // Determine the form prefix based on container ID
    const isVariantForm = productImagesContainer.id === 'variant-images';
    const formPrefix = isVariantForm ? 'product_variant' : 'product';
    const fieldPrefix = isVariantForm ? 'product_variant[product_images_attributes]' : 'product[product_images_attributes]';
    
    const newImageHtml = `
      <div class="product-image-item border border-gray-200 rounded-lg p-4 bg-gray-50">
        <div class="flex items-start space-x-4">
          <div class="flex-1 space-y-3">
            <input type="file" name="${fieldPrefix}[${imageIndex}][image]" accept="image/*" data-direct-upload="true" class="block w-full text-sm text-gray-700 file:mr-4 file:rounded-md file:border-0 file:bg-blue-50 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-blue-700 hover:file:bg-blue-100">
            <input type="hidden" name="${fieldPrefix}[${imageIndex}][_destroy]" value="false" class="destroy-field">
          </div>
          <div class="flex-shrink-0">
            <button type="button" class="remove-image-btn px-3 py-1 text-sm bg-red-600 text-white rounded-md hover:bg-red-700">Supprimer</button>
          </div>
        </div>
      </div>
    `;
    imageIndex++;
    return newImageHtml;
  }

  addImageBtn.addEventListener('click', function() {
    const emptyMessage = productImagesContainer.querySelector('.text-gray-500.text-center');
    if (emptyMessage) {
      emptyMessage.remove();
    }
    const newImageField = document.createElement('div');
    newImageField.innerHTML = createNewImageField();
    productImagesContainer.appendChild(newImageField.firstElementChild);
  });

  productImagesContainer.addEventListener('click', function(e) {
    if (e.target.classList.contains('remove-image-btn')) {
      const imageItem = e.target.closest('.product-image-item');
      const destroyField = imageItem.querySelector('.destroy-field');
      if (destroyField) {
        destroyField.value = '1';
        imageItem.style.display = 'none';
      } else {
        imageItem.remove();
      }
      if (productImagesContainer.querySelectorAll('.product-image-item:not([style*="display: none"])').length === 0) {
        const emptyMessage = document.createElement('div');
        emptyMessage.className = 'text-sm text-gray-500 text-center py-4';
        const isVariantForm = productImagesContainer.id === 'variant-images';
        emptyMessage.textContent = isVariantForm ? 'Aucune image pour cette variante' : 'Aucune image pour ce produit';
        productImagesContainer.appendChild(emptyMessage);
      }
    }
  });
}

// Auto-initialize if script is loaded directly (not as module import)
// This allows the script to work both ways
if (typeof window !== 'undefined') {
  // Initialize on DOMContentLoaded
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initProductImages);
  } else {
    // DOM already loaded, initialize immediately
    setTimeout(initProductImages, 0);
  }

  // Also initialize on Turbo events (for Rails with Turbo)
  if (typeof Turbo !== 'undefined') {
    document.addEventListener('turbo:load', initProductImages);
    document.addEventListener('turbo:render', initProductImages);
  }
}

