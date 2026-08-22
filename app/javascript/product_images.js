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
    
    const dragHandle = isVariantForm ? `
      <div class="flex-shrink-0 flex items-center justify-center w-8 h-8 text-gray-400">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8h16M4 16h16"></path>
        </svg>
      </div>
    ` : '';
    
    const draggableClass = isVariantForm ? 'draggable-item cursor-move hover:border-blue-400 transition-colors' : '';
    
    const newImageHtml = `
      <div class="product-image-item border border-gray-200 rounded-lg p-4 bg-gray-50 ${draggableClass}">
        <div class="flex items-start space-x-4">
          ${dragHandle}
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
    const insertedElement = productImagesContainer.appendChild(newImageField.firstElementChild);
    
    // Reinitialize drag and drop if needed
    if (productImagesContainer.id === 'variant-images') {
      initDragAndDrop(productImagesContainer);
    }
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

  // Initialize drag and drop for variant images
  if (productImagesContainer.id === 'variant-images') {
    initDragAndDrop(productImagesContainer);
  }
}

function initDragAndDrop(container) {
  const reorderUrl = container.dataset.reorderUrl;
  if (!reorderUrl) {
    return;
  }

  let draggedElement = null;
  let draggedIndex = null;

  // Make items draggable (only persisted images with data-image-id)
  const items = container.querySelectorAll('.product-image-item[data-image-id]');
  items.forEach((item, index) => {
    item.draggable = true;
    item.dataset.index = index;
    
    item.addEventListener('dragstart', function(e) {
      // Only allow dragging if this item has an image ID
      if (!this.dataset.imageId) {
        e.preventDefault();
        return false;
      }
      draggedElement = this;
      draggedIndex = Array.from(container.children).indexOf(this);
      this.style.opacity = '0.5';
      e.dataTransfer.effectAllowed = 'move';
      e.dataTransfer.setData('text/html', this.innerHTML);
    });

    item.addEventListener('dragend', function(e) {
      this.style.opacity = '';
      this.classList.remove('border-blue-500');
      // Remove drag-over class from all items
      container.querySelectorAll('.product-image-item').forEach(item => {
        item.classList.remove('border-blue-500', 'bg-blue-50');
      });
    });

    item.addEventListener('dragover', function(e) {
      if (e.preventDefault) {
        e.preventDefault();
      }
      // Only allow dropping on persisted images
      if (!this.dataset.imageId || !draggedElement?.dataset.imageId) {
        return false;
      }
      e.dataTransfer.dropEffect = 'move';
      
      // Highlight drop target
      if (this !== draggedElement) {
        this.classList.add('border-blue-500', 'bg-blue-50');
      }
      
      return false;
    });

    item.addEventListener('dragleave', function(e) {
      this.classList.remove('border-blue-500', 'bg-blue-50');
    });

    item.addEventListener('drop', function(e) {
      if (e.stopPropagation) {
        e.stopPropagation();
      }

      if (draggedElement !== this && draggedElement.dataset.imageId) {
        const allItems = Array.from(container.querySelectorAll('.product-image-item:not([style*="display: none"])'));
        const targetIndex = allItems.indexOf(this);
        const sourceIndex = allItems.indexOf(draggedElement);

        if (sourceIndex < targetIndex) {
          // Moving down
          container.insertBefore(draggedElement, this.nextSibling);
        } else {
          // Moving up
          container.insertBefore(draggedElement, this);
        }

        // Save new order (only for persisted images)
        saveImageOrder(container, reorderUrl);
      }

      this.classList.remove('border-blue-500', 'bg-blue-50');
      return false;
    });
  });
}

function saveImageOrder(container, reorderUrl) {
  const items = container.querySelectorAll('.product-image-item:not([style*="display: none"])');
  const imageIds = Array.from(items)
    .map(item => item.dataset.imageId)
    .filter(id => id); // Only include persisted images

  if (imageIds.length === 0) {
    return;
  }

  // Show saving indicator
  const savingIndicator = document.createElement('div');
  savingIndicator.className = 'fixed top-4 right-4 bg-blue-600 text-white px-4 py-2 rounded-md shadow-lg z-50';
  savingIndicator.textContent = 'Sauvegarde de l\'ordre...';
  document.body.appendChild(savingIndicator);

  fetch(reorderUrl, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
    },
    body: JSON.stringify({
      image_positions: imageIds
    })
  })
  .then(response => {
    if (response.ok) {
      savingIndicator.textContent = 'Ordre sauvegardé ✓';
      savingIndicator.className = 'fixed top-4 right-4 bg-green-600 text-white px-4 py-2 rounded-md shadow-lg z-50';
      setTimeout(() => {
        savingIndicator.remove();
      }, 2000);
    } else {
      throw new Error('Failed to save order');
    }
  })
  .catch(error => {
    console.error('Error saving image order:', error);
    savingIndicator.textContent = 'Erreur lors de la sauvegarde';
    savingIndicator.className = 'fixed top-4 right-4 bg-red-600 text-white px-4 py-2 rounded-md shadow-lg z-50';
    setTimeout(() => {
      savingIndicator.remove();
    }, 3000);
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

